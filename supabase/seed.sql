-- Puma Estaciones: datos de ejemplo (3 estaciones con 45 días de cortes, 1 estación sin gerente).
-- Ejecutar en el SQL Editor después de schema.sql.
--
-- ATENCIÓN: borra TODOS los datos de las tablas de la app y los usuarios de Auth que tengan perfil,
-- y los vuelve a crear con fechas relativas al día de hoy. Se puede ejecutar las veces que haga falta.
-- Todas las cuentas usan la contraseña Puma2026.
--
-- Con parcial2.sql instalado también se borran empleados, turnos y ventas de tienda:
-- ejecutar seed_parcial2.sql después para recrearlos.

do $$
declare
    c_tz constant text := 'America/El_Salvador';
    c_password constant text := 'Puma2026';
    c_history_days constant int := 45;
    c_supplier constant text := 'Puma Energy El Salvador';
    c_fuels constant text[] := array['diesel', 'regular', 'premium'];
    c_base constant double precision[] := array[110, 150, 70];
    c_price constant double precision[] := array[3.84, 3.88, 4.19];
    c_cost constant double precision[] := array[3.10, 2.95, 3.31];

    v_today date := (now() at time zone c_tz)::date;
    v_invoice int := 88000;
    s record;
    v_branch uuid;
    v_user uuid;
    v_cut uuid;
    v_day date;
    v_offset int;
    v_shift int;
    v_pumps int;
    v_is_today boolean;
    v_closes boolean;
    v_capacity double precision[];
    v_stock double precision[];
    v_sold double precision[];
    v_received double precision[];
    v_lost double precision[];
    v_gallons double precision[];
    v_qty double precision;
    v_fuel int;
    v_pump int;
begin
    -- Limpieza.
    delete from public.branches where true;
    delete from auth.users where id in (select id from public.profiles);

    -- Mismos datos en cada ejecución.
    perform setseed(0.2026);

    -- Gerente general.
    v_user := gen_random_uuid();
    perform private.create_auth_user(v_user, 'gerente@puma.sv', c_password);
    insert into public.profiles (id, first_name, last_name, email, role, dui, phone)
    values (v_user, 'Elena', 'Guevara', 'gerente@puma.sv', 'generalManager', '01234567-8', '7000-0001');

    for s in
        select * from (values
            ('Puma Escalón', 'SUC-001', 'Paseo General Escalón', 'San Salvador',
             array[10000, 12000, 8000]::double precision[], array[3500, 2150, 5480]::double precision[],
             1.0::double precision, 'Roberto', 'Martínez', 'rmartinez@puma.sv', '03456789-1', 4),
            ('Puma Santa Tecla', 'SUC-002', 'Carretera Panamericana km 12', 'Santa Tecla',
             array[10000, 12000, 8000]::double precision[], array[6200, 3840, 5680]::double precision[],
             0.85::double precision, 'Andrea', 'López', 'alopez@puma.sv', '02345678-9', null),
            ('Puma Soyapango', 'SUC-003', 'Bulevar del Ejército', 'Soyapango',
             array[8000, 10000, 6000]::double precision[], array[5100, 6300, 820]::double precision[],
             0.7::double precision, 'Carlos', 'Hernández', 'chernandez@puma.sv', '05678912-3', 2)
        ) as t (name, code, address, municipality, capacity, current_stock, volume_factor,
                first_name, last_name, email, dui, evening_pumps_today)
    loop
        v_capacity := s.capacity;
        v_stock := array[v_capacity[1] * 0.75, v_capacity[2] * 0.75, v_capacity[3] * 0.75];

        insert into public.branches (name, code, address, municipality, phone, created_at,
                                     diesel_capacity, regular_capacity, premium_capacity)
        values (s.name, s.code, s.address, s.municipality, '2200-0000',
                (v_today - (c_history_days + 10))::timestamp at time zone c_tz,
                v_capacity[1], v_capacity[2], v_capacity[3])
        returning id into v_branch;

        insert into public.pumps (branch_id, number)
        select v_branch, n from generate_series(1, 6) as n;

        v_user := gen_random_uuid();
        perform private.create_auth_user(v_user, s.email, c_password);
        insert into public.profiles (id, first_name, last_name, email, role, dui, phone, branch_id)
        values (v_user, s.first_name, s.last_name, s.email, 'branchManager', s.dui, '7100-0000', v_branch);

        -- Historial cerrado: cada día, ambos cortes, las 6 bombas.
        for v_offset in reverse c_history_days..0 loop
            v_day := v_today - v_offset;
            v_is_today := v_offset = 0;

            for v_shift in 1..2 loop
                v_pumps := 6;
                if v_is_today and v_shift = 2 then
                    -- Corte vespertino de hoy: parcial o sin iniciar.
                    continue when s.evening_pumps_today is null;
                    v_pumps := s.evening_pumps_today;
                end if;
                v_closes := not (v_is_today and v_shift = 2);

                insert into public.sales_cuts (branch_id, day, shift, opened_at)
                values (v_branch, v_day, v_shift,
                        (v_day + case when v_shift = 1 then time '06:00' else time '14:00' end) at time zone c_tz)
                returning id into v_cut;

                v_sold := array[0, 0, 0];
                v_received := array[0, 0, 0];
                v_lost := array[0, 0, 0];

                -- 1. Ventas por bomba.
                for v_pump in 1..v_pumps loop
                    v_gallons := array[0, 0, 0];
                    for v_fuel in 1..3 loop
                        v_gallons[v_fuel] := round((c_base[v_fuel] * s.volume_factor * (0.8 + random() * 0.4))::numeric, 2);
                        v_sold[v_fuel] := v_sold[v_fuel] + v_gallons[v_fuel];
                    end loop;
                    insert into public.pump_sales (cut_id, pump_number,
                        diesel_gallons, diesel_amount, regular_gallons, regular_amount, premium_gallons, premium_amount,
                        recorded_at)
                    values (v_cut, v_pump,
                        v_gallons[1], round((v_gallons[1] * c_price[1])::numeric, 2),
                        v_gallons[2], round((v_gallons[2] * c_price[2])::numeric, 2),
                        v_gallons[3], round((v_gallons[3] * c_price[3])::numeric, 2),
                        (v_day + case when v_shift = 1 then time '10:00' else time '18:00' end) at time zone c_tz);
                end loop;

                -- 2. Recepciones: en el corte matutino se reabastecen los tanques por debajo del 45 %.
                if v_shift = 1 and not v_is_today then
                    for v_fuel in 1..3 loop
                        if v_stock[v_fuel] < v_capacity[v_fuel] * 0.45 then
                            v_qty := floor((v_capacity[v_fuel] * 0.9 - v_stock[v_fuel]) / 1000) * 1000;
                            if v_qty > 0 then
                                v_invoice := v_invoice + 1;
                                insert into public.fuel_receptions (cut_id, fuel, gallons, cost_per_gallon,
                                                                    supplier, invoice_number, received_at)
                                values (v_cut, c_fuels[v_fuel], v_qty, c_cost[v_fuel], c_supplier,
                                        'F-' || v_invoice, (v_day + time '08:00') at time zone c_tz);
                                v_received[v_fuel] := v_received[v_fuel] + v_qty;
                            end if;
                        end if;
                    end loop;
                end if;

                -- 3. Pérdidas: merma pequeña cada 9 días y una fuga en Soyapango.
                if v_shift = 2 and v_offset % 9 = 4 then
                    v_fuel := 1 + floor(random() * 3)::int;
                    v_qty := round((8 + random() * 12)::numeric, 1);
                    insert into public.fuel_losses (cut_id, type, fuel, gallons, cost_per_gallon, pump_number, details, recorded_at)
                    values (v_cut, 'shrinkage', c_fuels[v_fuel], v_qty, c_cost[v_fuel], null,
                            'Evaporación registrada en la medición del tanque.', (v_day + time '18:00') at time zone c_tz);
                    v_lost[v_fuel] := v_lost[v_fuel] + v_qty;
                end if;
                if s.code = 'SUC-003' and v_offset = 2 and v_shift = 1 then
                    insert into public.fuel_losses (cut_id, type, fuel, gallons, cost_per_gallon, pump_number, details, recorded_at)
                    values (v_cut, 'leak', 'premium', 310, c_cost[3], 4,
                            'Manguera de Súper dañada; se aisló y se reportó a mantenimiento.', (v_day + time '10:00') at time zone c_tz);
                    v_lost[3] := v_lost[3] + 310;
                end if;
                if s.code = 'SUC-001' and v_is_today and v_shift = 2 then
                    insert into public.fuel_losses (cut_id, type, fuel, gallons, cost_per_gallon, pump_number, details, recorded_at)
                    values (v_cut, 'shrinkage', 'regular', 12, c_cost[2], null,
                            'Evaporación en tanque Regular.', (v_day + time '18:00') at time zone c_tz);
                end if;

                -- Se cierran todos los cortes menos el vespertino de hoy.
                if v_closes then
                    update public.sales_cuts
                    set status = 'closed',
                        closed_at = (v_day + case when v_shift = 1 then time '14:00' else time '22:00' end) at time zone c_tz,
                        opening_diesel = v_stock[1],
                        opening_regular = v_stock[2],
                        opening_premium = v_stock[3]
                    where id = v_cut;
                    for v_fuel in 1..3 loop
                        v_stock[v_fuel] := greatest(v_stock[v_fuel] + v_received[v_fuel] - v_sold[v_fuel] - v_lost[v_fuel], 0);
                    end loop;
                end if;
            end loop;
        end loop;

        -- Existencia actual ajustada para mostrar tanques en crítico, medio y óptimo.
        update public.branches
        set diesel_stock = s.current_stock[1],
            regular_stock = s.current_stock[2],
            premium_stock = s.current_stock[3]
        where id = v_branch;
    end loop;

    -- Una estación sin gerente y un gerente sin estación, para mostrar el flujo de vinculación.
    insert into public.branches (name, code, address, municipality, phone,
                                 diesel_capacity, regular_capacity, premium_capacity)
    values ('Puma Merliot', 'SUC-004', 'Calle Chiltiupán', 'Antiguo Cuscatlán', '2200-0004', 10000, 12000, 8000)
    returning id into v_branch;
    insert into public.pumps (branch_id, number)
    select v_branch, n from generate_series(1, 6) as n;

    v_user := gen_random_uuid();
    perform private.create_auth_user(v_user, 'gflores@puma.sv', c_password);
    insert into public.profiles (id, first_name, last_name, email, role, dui, phone)
    values (v_user, 'Gabriela', 'Flores', 'gflores@puma.sv', 'branchManager', '04567891-2', '7012-3456');
end;
$$;
