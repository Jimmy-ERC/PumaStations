-- Puma Estaciones: esquema de Supabase (tablas, RLS y funciones).
-- Ejecutar una sola vez en el SQL Editor del proyecto, antes de seed.sql.

create extension if not exists pgcrypto with schema extensions;

-- Funciones auxiliares fuera del esquema expuesto por la API.
create schema if not exists private;

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

create table public.branches (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    code text not null,
    address text not null,
    municipality text not null,
    phone text not null default '',
    created_at timestamptz not null default now(),
    diesel_capacity double precision not null check (diesel_capacity > 0),
    regular_capacity double precision not null check (regular_capacity > 0),
    premium_capacity double precision not null check (premium_capacity > 0),
    diesel_stock double precision not null default 0 check (diesel_stock >= 0),
    regular_stock double precision not null default 0 check (regular_stock >= 0),
    premium_stock double precision not null default 0 check (premium_stock >= 0)
);
create unique index branches_name_key on public.branches (lower(name));

-- Datos del usuario; la contraseña vive en auth.users (Supabase Auth).
create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    first_name text not null,
    last_name text not null,
    email text not null unique,
    role text not null check (role in ('generalManager', 'branchManager')),
    dui text not null default '',
    phone text not null default '',
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    branch_id uuid references public.branches (id) on delete set null
);
-- Cada estación tiene un solo gerente.
create unique index profiles_branch_key on public.profiles (branch_id) where branch_id is not null;

create table public.pumps (
    id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references public.branches (id) on delete cascade,
    number smallint not null check (number between 1 and 6),
    unique (branch_id, number)
);

create table public.sales_cuts (
    id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references public.branches (id) on delete cascade,
    day date not null,
    shift smallint not null check (shift in (1, 2)),
    status text not null default 'open' check (status in ('open', 'closed')),
    opened_at timestamptz not null default now(),
    closed_at timestamptz,
    opening_diesel double precision not null default 0,
    opening_regular double precision not null default 0,
    opening_premium double precision not null default 0,
    unique (branch_id, day, shift)
);

create table public.pump_sales (
    id uuid primary key default gen_random_uuid(),
    cut_id uuid not null references public.sales_cuts (id) on delete cascade,
    pump_number smallint not null check (pump_number between 1 and 6),
    is_out_of_service boolean not null default false,
    diesel_gallons double precision not null default 0 check (diesel_gallons >= 0),
    diesel_amount double precision not null default 0 check (diesel_amount >= 0),
    regular_gallons double precision not null default 0 check (regular_gallons >= 0),
    regular_amount double precision not null default 0 check (regular_amount >= 0),
    premium_gallons double precision not null default 0 check (premium_gallons >= 0),
    premium_amount double precision not null default 0 check (premium_amount >= 0),
    recorded_at timestamptz not null default now(),
    unique (cut_id, pump_number)
);

create table public.fuel_receptions (
    id uuid primary key default gen_random_uuid(),
    cut_id uuid not null references public.sales_cuts (id) on delete cascade,
    fuel text not null check (fuel in ('diesel', 'regular', 'premium')),
    gallons double precision not null check (gallons > 0),
    cost_per_gallon double precision not null check (cost_per_gallon > 0),
    supplier text not null,
    invoice_number text not null,
    received_at timestamptz not null default now()
);
create index fuel_receptions_cut_idx on public.fuel_receptions (cut_id);

create table public.fuel_losses (
    id uuid primary key default gen_random_uuid(),
    cut_id uuid not null references public.sales_cuts (id) on delete cascade,
    type text not null check (type in ('shrinkage', 'leak', 'technicalFailure', 'spill')),
    fuel text not null check (fuel in ('diesel', 'regular', 'premium')),
    gallons double precision not null check (gallons > 0),
    cost_per_gallon double precision not null check (cost_per_gallon >= 0),
    -- null = tanque de almacenamiento
    pump_number smallint check (pump_number between 1 and 6),
    details text not null default '',
    recorded_at timestamptz not null default now()
);
create index fuel_losses_cut_idx on public.fuel_losses (cut_id);

-- ---------------------------------------------------------------------------
-- Funciones auxiliares para las políticas (security definer: leen profiles sin recursión de RLS)
-- ---------------------------------------------------------------------------

create or replace function private.is_general_manager()
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.profiles
        where id = (select auth.uid()) and role = 'generalManager' and is_active
    );
$$;

-- Sucursal del gerente de sucursal activo que hace la consulta (null en otro caso).
create or replace function private.my_branch_id()
returns uuid
language sql stable security definer set search_path = ''
as $$
    select branch_id from public.profiles
    where id = (select auth.uid()) and role = 'branchManager' and is_active;
$$;

create or replace function private.can_view_cut(p_cut_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.sales_cuts c
        where c.id = p_cut_id
          and (private.is_general_manager() or c.branch_id = private.my_branch_id())
    );
$$;

-- Un corte cerrado queda bloqueado: solo se editan movimientos de cortes abiertos de la propia sucursal.
create or replace function private.can_edit_cut(p_cut_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.sales_cuts c
        where c.id = p_cut_id
          and c.status = 'open'
          and c.branch_id = private.my_branch_id()
    );
$$;

-- Crea un usuario de Supabase Auth con correo ya confirmado.
create or replace function private.create_auth_user(p_id uuid, p_email text, p_password text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
    insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, recovery_token, email_change, email_change_token_new
    ) values (
        '00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email,
        extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
        '{"provider": "email", "providers": ["email"]}'::jsonb, '{}'::jsonb, now(), now(),
        '', '', '', ''
    );

    insert into auth.identities (
        id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) values (
        gen_random_uuid(), p_id, p_id::text,
        jsonb_build_object('sub', p_id::text, 'email', p_email, 'email_verified', true, 'phone_verified', false),
        'email', now(), now(), now()
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: alta y edición de gerentes de sucursal (solo el gerente general)
-- ---------------------------------------------------------------------------

create or replace function public.save_manager(
    p_id uuid,
    p_email text,
    p_password text,
    p_first_name text,
    p_last_name text,
    p_dui text,
    p_phone text,
    p_is_active boolean,
    p_branch_id uuid
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    v_email text := lower(trim(p_email));
    v_role text;
begin
    if not private.is_general_manager() then
        raise exception 'Solo el gerente general puede administrar gerentes.' using errcode = '42501';
    end if;

    select role into v_role from public.profiles where id = p_id;

    if v_role is null then
        if length(coalesce(p_password, '')) < 6 then
            raise exception 'La contraseña debe tener al menos 6 caracteres.' using errcode = '22023';
        end if;
        perform private.create_auth_user(p_id, v_email, p_password);
        insert into public.profiles (id, first_name, last_name, email, role, dui, phone, is_active, branch_id)
        values (p_id, p_first_name, p_last_name, v_email, 'branchManager', p_dui, p_phone, p_is_active, p_branch_id);
    else
        if v_role <> 'branchManager' then
            raise exception 'Solo se pueden editar gerentes de sucursal.' using errcode = '42501';
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
            is_active = p_is_active,
            branch_id = p_branch_id
        where id = p_id;
    end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

grant usage on schema private to authenticated;
revoke execute on all functions in schema private from public, anon;
grant execute on function private.is_general_manager() to authenticated;
grant execute on function private.my_branch_id() to authenticated;
grant execute on function private.can_view_cut(uuid) to authenticated;
grant execute on function private.can_edit_cut(uuid) to authenticated;

revoke execute on function public.save_manager(uuid, text, text, text, text, text, text, boolean, uuid) from public, anon;
grant execute on function public.save_manager(uuid, text, text, text, text, text, text, boolean, uuid) to authenticated;

revoke all on public.branches, public.profiles, public.pumps, public.sales_cuts,
    public.pump_sales, public.fuel_receptions, public.fuel_losses from anon;
grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.branches, public.pumps, public.sales_cuts,
    public.pump_sales, public.fuel_receptions, public.fuel_losses to authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security: el gerente general ve todo; el de sucursal solo su estación
-- ---------------------------------------------------------------------------

alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.pumps enable row level security;
alter table public.sales_cuts enable row level security;
alter table public.pump_sales enable row level security;
alter table public.fuel_receptions enable row level security;
alter table public.fuel_losses enable row level security;

-- profiles: lectura propia o del gerente general; se escribe solo con save_manager.
create policy profiles_select on public.profiles for select to authenticated
    using (id = (select auth.uid()) or (select private.is_general_manager()));

-- branches
create policy branches_select on public.branches for select to authenticated
    using ((select private.is_general_manager()) or id = (select private.my_branch_id()));
create policy branches_insert on public.branches for insert to authenticated
    with check ((select private.is_general_manager()));
-- El gerente de sucursal actualiza las existencias de sus tanques al cerrar un corte.
create policy branches_update on public.branches for update to authenticated
    using ((select private.is_general_manager()) or id = (select private.my_branch_id()))
    with check ((select private.is_general_manager()) or id = (select private.my_branch_id()));
create policy branches_delete on public.branches for delete to authenticated
    using ((select private.is_general_manager()));

-- pumps
create policy pumps_select on public.pumps for select to authenticated
    using ((select private.is_general_manager()) or branch_id = (select private.my_branch_id()));
create policy pumps_insert on public.pumps for insert to authenticated
    with check ((select private.is_general_manager()));

-- sales_cuts: solo el gerente de la sucursal los crea y cierra; cerrado = bloqueado.
create policy sales_cuts_select on public.sales_cuts for select to authenticated
    using ((select private.is_general_manager()) or branch_id = (select private.my_branch_id()));
create policy sales_cuts_insert on public.sales_cuts for insert to authenticated
    with check (branch_id = (select private.my_branch_id()));
create policy sales_cuts_update on public.sales_cuts for update to authenticated
    using (branch_id = (select private.my_branch_id()) and status = 'open')
    with check (branch_id = (select private.my_branch_id()));

-- Movimientos del corte: ventas por bomba, recepciones y pérdidas.
create policy pump_sales_select on public.pump_sales for select to authenticated
    using (private.can_view_cut(cut_id));
create policy pump_sales_insert on public.pump_sales for insert to authenticated
    with check (private.can_edit_cut(cut_id));
create policy pump_sales_update on public.pump_sales for update to authenticated
    using (private.can_edit_cut(cut_id)) with check (private.can_edit_cut(cut_id));
create policy pump_sales_delete on public.pump_sales for delete to authenticated
    using (private.can_edit_cut(cut_id));

create policy fuel_receptions_select on public.fuel_receptions for select to authenticated
    using (private.can_view_cut(cut_id));
create policy fuel_receptions_insert on public.fuel_receptions for insert to authenticated
    with check (private.can_edit_cut(cut_id));
create policy fuel_receptions_update on public.fuel_receptions for update to authenticated
    using (private.can_edit_cut(cut_id)) with check (private.can_edit_cut(cut_id));
create policy fuel_receptions_delete on public.fuel_receptions for delete to authenticated
    using (private.can_edit_cut(cut_id));

create policy fuel_losses_select on public.fuel_losses for select to authenticated
    using (private.can_view_cut(cut_id));
create policy fuel_losses_insert on public.fuel_losses for insert to authenticated
    with check (private.can_edit_cut(cut_id));
create policy fuel_losses_update on public.fuel_losses for update to authenticated
    using (private.can_edit_cut(cut_id)) with check (private.can_edit_cut(cut_id));
create policy fuel_losses_delete on public.fuel_losses for delete to authenticated
    using (private.can_edit_cut(cut_id));
