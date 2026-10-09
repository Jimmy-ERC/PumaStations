-- Puma Estaciones · Parcial 2: datos de ejemplo de catálogo, empleados, turnos y ventas de tienda.
-- Ejecutar en el SQL Editor después de parcial2.sql (y de seed.sql si se recargan los datos base).
--
-- ATENCIÓN: borra las ventas de tienda, entradas de inventario, turnos, empleados y catálogo, y los
-- vuelve a crear con fechas relativas al día de hoy. No toca sucursales, gerentes ni cortes.
-- Crea 3 empleados en cada una de las primeras 3 estaciones con gerente. Contraseña: Puma2026.

do $$
declare
    c_tz constant text := 'America/El_Salvador';
    c_password constant text := 'Puma2026';
    c_history_days constant int := 14;
    c_future_days constant int := 6;
    -- Productos con poca existencia, para mostrar los avisos de inventario.
    c_scarce constant text[] := array['Limpiaparabrisas 1 L', 'Aditivo para combustible'];
    -- 3 empleados por estación: turno matutino, turno vespertino y mantenimiento.
    c_first constant text[] := array['Mario', 'Sofía', 'Diego', 'Karla', 'Luis', 'Marta', 'José', 'Paola', 'Óscar'];
    c_last constant text[] := array['Rivas', 'Campos', 'Molina', 'Pineda', 'Aguilar', 'Cruz', 'Ramírez', 'Mejía', 'Vásquez'];
    c_email constant text[] := array['mrivas', 'scampos', 'dmolina', 'kpineda', 'laguilar', 'mcruz', 'jramirez', 'pmejia', 'ovasquez'];
    c_job constant text[] := array['Pistero', 'Cajera de tienda', 'Técnico de mantenimiento'];
    -- Día de descanso de cada puesto (0 = domingo).
    c_rest_day constant int[] := array[0, 1, 2];

    v_today date := (now() at time zone c_tz)::date;
    b record;
    v_staff uuid[];
    v_user uuid;
    v_sale uuid;
    v_item uuid;
    v_price double precision;
    v_day date;
    v_offset int;
    v_shift int;
    v_slot int;
    v_n int;
    v_start timestamptz;
    v_sold_at timestamptz;
    v_seller uuid;
begin
    -- Limpieza.
    delete from public.sales where true;
    delete from public.stock_entries where true;
    delete from public.work_shifts where true;
    delete from auth.users where id in (select id from public.profiles where role = 'employee');
    delete from public.catalog_items where true;

    -- Mismos datos en cada ejecución.
    perform setseed(0.2027);

    insert into public.catalog_items (name, category, detail, price, min_stock) values
        ('Agua embotellada 600 ml', 'convenience', 'Botella', 0.75, 12),
        ('Gaseosa 355 ml', 'convenience', 'Lata', 1.00, 12),
        ('Bebida energizante', 'convenience', 'Lata 250 ml', 2.25, 8),
        ('Café americano 12 oz', 'convenience', 'Vaso', 1.50, 10),
        ('Sándwich de jamón y queso', 'convenience', 'Unidad', 2.75, 6),
        ('Snack de papas', 'convenience', 'Bolsa 45 g', 1.25, 10),
        ('Galletas', 'convenience', 'Paquete', 0.90, 10),
        ('Hielo 5 lb', 'convenience', 'Bolsa', 1.75, 6),
        ('Aceite Puma 20W-50 1 L', 'lubricant', 'Mineral, motor a gasolina', 6.50, 8),
        ('Aceite sintético 5W-30 1 L', 'lubricant', 'Sintético, motor a gasolina', 11.90, 6),
        ('Aceite para moto 2T', 'lubricant', 'Botella 1 L', 5.25, 6),
        ('Líquido de frenos DOT 4', 'lubricant', 'Botella 355 ml', 4.75, 5),
        ('Refrigerante anticongelante 1 gal', 'lubricant', 'Listo para usar', 9.50, 5),
        ('Limpiaparabrisas 1 L', 'lubricant', 'Botella', 3.25, 6),
        ('Aditivo para combustible', 'lubricant', 'Botella 350 ml', 5.95, 4),
        ('Revisión y cambio de aceite', 'service', 'Mano de obra, filtro y revisión de niveles', 25.00, 0),
        ('Revisión y cambio de anticongelante', 'service', 'Drenado y llenado del sistema de enfriamiento', 18.00, 0),
        ('Revisión y cambio de líquido de frenos', 'service', 'Purga y llenado del sistema de frenos', 22.00, 0),
        ('Llenado o ajuste de aire para neumáticos', 'service', 'Calibración de las 4 llantas', 1.00, 0);

    for b in
        select t.id, t.rn from (
            select br.id, row_number() over (order by br.code, br.name) as rn
            from public.branches br
            where exists (select 1 from public.profiles p where p.branch_id = br.id and p.role = 'branchManager')
        ) as t
        where t.rn <= 3
        order by t.rn
    loop
        -- Empleados.
        v_staff := array[]::uuid[];
        for v_slot in 1..3 loop
            v_n := (b.rn - 1) * 3 + v_slot;
            v_user := gen_random_uuid();
            perform private.create_auth_user(v_user, c_email[v_n] || '@puma.sv', c_password);
            insert into public.profiles (id, first_name, last_name, email, role, dui, phone, job_title, branch_id)
            values (v_user, c_first[v_n], c_last[v_n], c_email[v_n] || '@puma.sv', 'employee',
                    '0' || (6000000 + v_n * 111111) || '-' || v_n, '7200-00' || lpad(v_n::text, 2, '0'),
                    c_job[v_slot], b.id);
            v_staff := v_staff || v_user;
        end loop;

        -- Inventario de tienda: una entrada inicial y un reabastecimiento.
        insert into public.stock_entries (branch_id, item_id, quantity, unit_cost, note, received_at)
        select b.id, c.id, 80, round((c.price * 0.7)::numeric, 2), 'Inventario inicial',
               (v_today - (c_history_days + 1) + time '09:00') at time zone c_tz
        from public.catalog_items c
        where c.category <> 'service' and c.name <> all (c_scarce);

        insert into public.stock_entries (branch_id, item_id, quantity, unit_cost, note, received_at)
        select b.id, c.id, 24, round((c.price * 0.7)::numeric, 2), 'Reabastecimiento semanal',
               (v_today - 5 + time '09:00') at time zone c_tz
        from public.catalog_items c
        where c.category <> 'service' and c.name <> all (c_scarce);

        -- Limpiaparabrisas queda bajo el mínimo; el aditivo queda agotado (sin entradas).
        insert into public.stock_entries (branch_id, item_id, quantity, unit_cost, note, received_at)
        select b.id, c.id, 4, round((c.price * 0.7)::numeric, 2), 'Inventario inicial',
               (v_today - (c_history_days + 1) + time '09:00') at time zone c_tz
        from public.catalog_items c
        where c.name = c_scarce[1];

        for v_offset in reverse c_history_days..(-c_future_days) loop
            v_day := v_today - v_offset;

            -- Turnos: puesto 1 en la mañana, puesto 2 en la tarde y puesto 3 cubre los descansos.
            for v_slot in 1..3 loop
                continue when extract(dow from v_day)::int = c_rest_day[v_slot];
                v_shift := case
                    when v_slot = 1 then 1
                    when v_slot = 2 then 2
                    when extract(dow from v_day)::int = c_rest_day[2] then 2
                    else 1
                end;
                v_start := (v_day + case when v_shift = 1 then time '06:00' else time '14:00' end) at time zone c_tz;
                insert into public.work_shifts (branch_id, employee_id, day, shift, check_in_at, check_out_at)
                values (
                    b.id, v_staff[v_slot], v_day, v_shift,
                    -- Hoy: el turno matutino ya marcó entrada; el vespertino aún no.
                    case when v_offset > 0 or (v_offset = 0 and v_shift = 1)
                         then v_start + make_interval(mins => floor(random() * 10)::int) end,
                    case when v_offset > 0 then v_start + interval '8 hours' end
                );
            end loop;

            continue when v_offset < 0;

            -- Ventas de tienda: 3 por turno, de 1 a 3 productos cada una.
            for v_shift in 1..2 loop
                v_seller := case
                    when extract(dow from v_day)::int = c_rest_day[v_shift] then v_staff[3]
                    else v_staff[v_shift]
                end;
                v_start := (v_day + case when v_shift = 1 then time '06:00' else time '14:00' end) at time zone c_tz;
                for v_n in 1..3 loop
                    v_sold_at := v_start + make_interval(mins => floor(random() * 470)::int);
                    continue when v_sold_at > now();
                    insert into public.sales (branch_id, seller_id, kind, payment_method, sold_at)
                    values (b.id, v_seller, 'store', case when random() < 0.6 then 'cash' else 'card' end, v_sold_at)
                    returning id into v_sale;
                    for v_item, v_price in
                        select c.id, c.price from public.catalog_items c
                        where c.category <> 'service' and c.name <> all (c_scarce)
                        order by random()
                        limit 1 + floor(random() * 3)::int
                    loop
                        insert into public.sale_items (sale_id, item_id, quantity, unit_price)
                        values (v_sale, v_item, 1 + floor(random() * 2)::int, v_price);
                    end loop;
                end loop;
            end loop;

            -- Mantenimiento: 2 órdenes al día, de 1 o 2 servicios.
            for v_n in 1..2 loop
                v_sold_at := (v_day + time '08:00') at time zone c_tz + make_interval(mins => floor(random() * 600)::int);
                continue when v_sold_at > now();
                insert into public.sales (branch_id, seller_id, kind, payment_method, vehicle_plate, sold_at)
                values (b.id, v_staff[3], 'service', case when random() < 0.5 then 'cash' else 'card' end,
                        'P' || lpad(floor(random() * 1000)::int::text, 3, '0') || '-' || lpad(floor(random() * 1000)::int::text, 3, '0'),
                        v_sold_at)
                returning id into v_sale;
                for v_item, v_price in
                    select c.id, c.price from public.catalog_items c
                    where c.category = 'service'
                    order by random()
                    limit 1 + floor(random() * 2)::int
                loop
                    insert into public.sale_items (sale_id, item_id, quantity, unit_price)
                    values (v_sale, v_item, 1, v_price);
                end loop;
            end loop;
        end loop;
    end loop;
end;
$$;
