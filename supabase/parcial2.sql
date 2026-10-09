-- Puma Estaciones · Parcial 2: empleados, turnos, tienda (conveniencia y lubricantes) y mantenimiento.
-- Migración incremental: se ejecuta una vez en el SQL Editor sobre la base que ya tiene schema.sql.
-- No borra datos; se puede volver a ejecutar sin problema.

-- ---------------------------------------------------------------------------
-- Rol Empleado
-- ---------------------------------------------------------------------------

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
    check (role in ('generalManager', 'branchManager', 'employee'));
alter table public.profiles add column if not exists job_title text not null default '';

-- Cada estación tiene un solo gerente, pero varios empleados.
drop index if exists public.profiles_branch_key;
create unique index profiles_branch_key on public.profiles (branch_id)
    where branch_id is not null and role = 'branchManager';

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

-- Turno de trabajo de un empleado: un día y uno de los dos turnos (1 matutino, 2 vespertino).
create table if not exists public.work_shifts (
    id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references public.branches (id) on delete cascade,
    employee_id uuid not null references public.profiles (id) on delete cascade,
    day date not null,
    shift smallint not null check (shift in (1, 2)),
    check_in_at timestamptz,
    check_out_at timestamptz,
    created_at timestamptz not null default now(),
    unique (employee_id, day, shift),
    check (check_out_at is null or check_in_at is not null)
);
create index if not exists work_shifts_branch_day_idx on public.work_shifts (branch_id, day);

-- Catálogo de la franquicia: productos de conveniencia, lubricantes y servicios de mantenimiento.
create table if not exists public.catalog_items (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    category text not null check (category in ('convenience', 'lubricant', 'service')),
    detail text not null default '',
    price double precision not null check (price >= 0),
    -- Existencia mínima por sucursal antes de avisar (no aplica a servicios).
    min_stock integer not null default 0 check (min_stock >= 0),
    is_active boolean not null default true,
    created_at timestamptz not null default now()
);
create unique index if not exists catalog_items_name_key on public.catalog_items (lower(name));

-- Entradas de inventario de tienda. Existencia = entradas − unidades vendidas.
create table if not exists public.stock_entries (
    id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references public.branches (id) on delete cascade,
    item_id uuid not null references public.catalog_items (id) on delete restrict,
    quantity integer not null check (quantity > 0),
    unit_cost double precision not null default 0 check (unit_cost >= 0),
    note text not null default '',
    received_at timestamptz not null default now()
);
create index if not exists stock_entries_branch_idx on public.stock_entries (branch_id, item_id);

-- Venta de tienda ('store') u orden de mantenimiento ('service').
create table if not exists public.sales (
    id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references public.branches (id) on delete cascade,
    seller_id uuid references public.profiles (id) on delete set null,
    kind text not null check (kind in ('store', 'service')),
    payment_method text not null check (payment_method in ('cash', 'card')),
    vehicle_plate text not null default '',
    sold_at timestamptz not null default now()
);
create index if not exists sales_branch_idx on public.sales (branch_id, sold_at);

create table if not exists public.sale_items (
    id uuid primary key default gen_random_uuid(),
    sale_id uuid not null references public.sales (id) on delete cascade,
    item_id uuid not null references public.catalog_items (id) on delete restrict,
    quantity integer not null check (quantity > 0),
    unit_price double precision not null check (unit_price >= 0)
);
create index if not exists sale_items_sale_idx on public.sale_items (sale_id);
create index if not exists sale_items_item_idx on public.sale_items (item_id);

-- ---------------------------------------------------------------------------
-- Funciones auxiliares
-- ---------------------------------------------------------------------------

-- Sucursal donde trabaja quien consulta: gerente de sucursal o empleado activo (null en otro caso).
create or replace function private.my_work_branch_id()
returns uuid
language sql stable security definer set search_path = ''
as $$
    select branch_id from public.profiles
    where id = (select auth.uid()) and role in ('branchManager', 'employee') and is_active;
$$;

create or replace function private.is_employee_of(p_employee_id uuid, p_branch_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.profiles
        where id = p_employee_id and role = 'employee' and branch_id = p_branch_id
    );
$$;

create or replace function private.can_view_sale(p_sale_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.sales s
        where s.id = p_sale_id
          and (private.is_general_manager() or s.branch_id = private.my_work_branch_id())
    );
$$;

-- Solo quien registró la venta le agrega sus líneas.
create or replace function private.owns_sale(p_sale_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.sales s
        where s.id = p_sale_id
          and s.seller_id = (select auth.uid())
          and s.branch_id = private.my_work_branch_id()
    );
$$;

-- El empleado solo marca su entrada y salida; el día y el turno los define el gerente.
create or replace function private.guard_work_shift_update()
returns trigger
language plpgsql set search_path = ''
as $$
begin
    if new.branch_id <> old.branch_id or new.employee_id <> old.employee_id then
        raise exception 'No se puede cambiar el empleado ni la sucursal de un turno.' using errcode = '42501';
    end if;
    if (new.day <> old.day or new.shift <> old.shift) and private.my_branch_id() is null then
        raise exception 'Solo el gerente de sucursal puede cambiar un turno.' using errcode = '42501';
    end if;
    return new;
end;
$$;

drop trigger if exists work_shifts_guard_update on public.work_shifts;
create trigger work_shifts_guard_update
    before update on public.work_shifts
    for each row execute function private.guard_work_shift_update();

-- No se vende más de lo que hay: existencia = entradas − vendido (los servicios no llevan inventario).
create or replace function private.check_sale_item_stock()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    v_branch uuid;
    v_category text;
    v_name text;
    v_available integer;
begin
    select category, name into v_category, v_name from public.catalog_items where id = new.item_id;
    if v_category = 'service' then
        return new;
    end if;

    select branch_id into v_branch from public.sales where id = new.sale_id;

    select coalesce((select sum(e.quantity) from public.stock_entries e
                     where e.branch_id = v_branch and e.item_id = new.item_id), 0)
         - coalesce((select sum(i.quantity) from public.sale_items i
                     join public.sales s on s.id = i.sale_id
                     where s.branch_id = v_branch and i.item_id = new.item_id), 0)
    into v_available;

    if new.quantity > v_available then
        raise exception 'Existencias insuficientes de %: quedan %.', v_name, v_available using errcode = '23514';
    end if;
    return new;
end;
$$;

drop trigger if exists sale_items_check_stock on public.sale_items;
create trigger sale_items_check_stock
    before insert on public.sale_items
    for each row execute function private.check_sale_item_stock();

-- ---------------------------------------------------------------------------
-- RPC: alta y edición de empleados (solo el gerente de la sucursal, para su estación)
-- ---------------------------------------------------------------------------

create or replace function public.save_employee(
    p_id uuid,
    p_email text,
    p_password text,
    p_first_name text,
    p_last_name text,
    p_dui text,
    p_phone text,
    p_job_title text,
    p_is_active boolean
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    v_email text := lower(trim(p_email));
    v_branch uuid := private.my_branch_id();
    v_role text;
    v_current_branch uuid;
begin
    if v_branch is null then
        raise exception 'Solo el gerente de una sucursal puede administrar empleados.' using errcode = '42501';
    end if;
    if exists (select 1 from auth.users where email = v_email and id <> p_id) then
        raise exception 'El correo % ya está registrado.', v_email using errcode = '23505';
    end if;

    select role, branch_id into v_role, v_current_branch from public.profiles where id = p_id;

    if v_role is null then
        if length(coalesce(p_password, '')) < 6 then
            raise exception 'La contraseña debe tener al menos 6 caracteres.' using errcode = '22023';
        end if;
        perform private.create_auth_user(p_id, v_email, p_password);
        insert into public.profiles (id, first_name, last_name, email, role, dui, phone, job_title, is_active, branch_id)
        values (p_id, p_first_name, p_last_name, v_email, 'employee', p_dui, p_phone, p_job_title, p_is_active, v_branch);
    else
        if v_role <> 'employee' or v_current_branch is distinct from v_branch then
            raise exception 'Solo puedes editar empleados de tu sucursal.' using errcode = '42501';
        end if;
        if coalesce(p_password, '') <> '' and length(p_password) < 6 then
            raise exception 'La contraseña debe tener al menos 6 caracteres.' using errcode = '22023';
        end if;

        update auth.users
        set email = v_email,
            encrypted_password = case
                when coalesce(p_password, '') = '' then encrypted_password
                else extensions.crypt(p_password, extensions.gen_salt('bf'))
            end,
            updated_at = now()
        where id = p_id;

        update auth.identities
        set identity_data = identity_data || jsonb_build_object('email', v_email),
            updated_at = now()
        where user_id = p_id and provider = 'email';

        update public.profiles
        set first_name = p_first_name,
            last_name = p_last_name,
            email = v_email,
            dui = p_dui,
            phone = p_phone,
            job_title = p_job_title,
            is_active = p_is_active
        where id = p_id;
    end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema private from public, anon;
grant execute on function private.my_work_branch_id() to authenticated;
grant execute on function private.is_employee_of(uuid, uuid) to authenticated;
grant execute on function private.can_view_sale(uuid) to authenticated;
grant execute on function private.owns_sale(uuid) to authenticated;

revoke execute on function public.save_employee(uuid, text, text, text, text, text, text, text, boolean) from public, anon;
grant execute on function public.save_employee(uuid, text, text, text, text, text, text, text, boolean) to authenticated;

revoke all on public.work_shifts, public.catalog_items, public.stock_entries, public.sales, public.sale_items from anon;
grant select, insert, update, delete on public.work_shifts to authenticated;
grant select, insert, update on public.catalog_items to authenticated;
grant select, insert on public.stock_entries, public.sales, public.sale_items to authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.work_shifts enable row level security;
alter table public.catalog_items enable row level security;
alter table public.stock_entries enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;

-- profiles: además, el gerente de sucursal ve a los empleados de su estación.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
    using (
        id = (select auth.uid())
        or (select private.is_general_manager())
        or (role = 'employee' and branch_id = (select private.my_branch_id()))
    );

-- branches: el empleado ve la estación donde trabaja (solo el gerente la actualiza).
drop policy if exists branches_select on public.branches;
create policy branches_select on public.branches for select to authenticated
    using ((select private.is_general_manager()) or id = (select private.my_work_branch_id()));

-- work_shifts: el gerente de sucursal los asigna; el empleado ve los suyos y marca entrada y salida.
drop policy if exists work_shifts_select on public.work_shifts;
create policy work_shifts_select on public.work_shifts for select to authenticated
    using (
        (select private.is_general_manager())
        or branch_id = (select private.my_branch_id())
        or employee_id = (select auth.uid())
    );
drop policy if exists work_shifts_insert on public.work_shifts;
create policy work_shifts_insert on public.work_shifts for insert to authenticated
    with check (branch_id = (select private.my_branch_id()) and private.is_employee_of(employee_id, branch_id));
drop policy if exists work_shifts_update on public.work_shifts;
create policy work_shifts_update on public.work_shifts for update to authenticated
    using (branch_id = (select private.my_branch_id()) or employee_id = (select auth.uid()))
    with check (branch_id = (select private.my_branch_id()) or employee_id = (select auth.uid()));
drop policy if exists work_shifts_delete on public.work_shifts;
create policy work_shifts_delete on public.work_shifts for delete to authenticated
    using (branch_id = (select private.my_branch_id()));

-- catalog_items: todos lo consultan; solo el gerente general define productos, servicios y precios.
drop policy if exists catalog_items_select on public.catalog_items;
create policy catalog_items_select on public.catalog_items for select to authenticated
    using (true);
drop policy if exists catalog_items_insert on public.catalog_items;
create policy catalog_items_insert on public.catalog_items for insert to authenticated
    with check ((select private.is_general_manager()));
drop policy if exists catalog_items_update on public.catalog_items;
create policy catalog_items_update on public.catalog_items for update to authenticated
    using ((select private.is_general_manager()))
    with check ((select private.is_general_manager()));

-- stock_entries: el gerente de sucursal reabastece su tienda.
drop policy if exists stock_entries_select on public.stock_entries;
create policy stock_entries_select on public.stock_entries for select to authenticated
    using ((select private.is_general_manager()) or branch_id = (select private.my_work_branch_id()));
drop policy if exists stock_entries_insert on public.stock_entries;
create policy stock_entries_insert on public.stock_entries for insert to authenticated
    with check (branch_id = (select private.my_branch_id()));

-- sales: las registra el personal de la sucursal a su nombre; no se editan ni se borran.
drop policy if exists sales_select on public.sales;
create policy sales_select on public.sales for select to authenticated
    using ((select private.is_general_manager()) or branch_id = (select private.my_work_branch_id()));
drop policy if exists sales_insert on public.sales;
create policy sales_insert on public.sales for insert to authenticated
    with check (branch_id = (select private.my_work_branch_id()) and seller_id = (select auth.uid()));

drop policy if exists sale_items_select on public.sale_items;
create policy sale_items_select on public.sale_items for select to authenticated
    using (private.can_view_sale(sale_id));
drop policy if exists sale_items_insert on public.sale_items;
create policy sale_items_insert on public.sale_items for insert to authenticated
    with check (private.owns_sale(sale_id));
