# Puma Estaciones: gestión de franquicia de gasolineras (SwiftUI + MVVM)

App nativa para iPhone de la franquicia de estaciones **Puma Energy** en El Salvador. Maneja tres combustibles: Súper, Regular y Diésel. Sigue las indicaciones del documento *LABORATORIO 22* y el diseño v2 de Figma.

## Requisitos

- Xcode 16 o superior (preparado para Xcode 16.4).
- iOS 17.0 o superior (simulador o iPhone).
- Un proyecto de Supabase (base de datos y autenticación).
- Sin dependencias externas: usa SwiftUI, SwiftData, Swift Charts y `URLSession` contra la API de Supabase.

## Configurar Supabase

1. En el **SQL Editor** del proyecto ejecuta `supabase/schema.sql` (tablas, políticas RLS y funciones).
2. Ejecuta `supabase/parcial2.sql`: agrega el rol Empleado, los turnos, el catálogo, el inventario de tienda y las ventas. Es una migración incremental, no borra datos y se puede volver a ejecutar.
3. Ejecuta `supabase/seed.sql` para cargar los datos de ejemplo: 3 estaciones operando con 45 días de cortes y 1 estación sin gerente. Se puede volver a ejecutar cuando se quiera: borra todo y lo recrea con fechas relativas al día de hoy.
4. Ejecuta `supabase/seed_parcial2.sql` para cargar el catálogo, 3 empleados por estación, sus turnos y 2 semanas de ventas de tienda y mantenimiento. También se puede repetir: solo borra y recrea esos datos.
5. Copia `supabase/Supabase.example.plist` a `PumaStations/Supabase.plist` y escribe la **Project URL** y la **publishable key** (Settings → API Keys). Ese archivo está en `.gitignore`. Nunca uses la *secret key* en la app.
6. Recomendado: en Authentication → Sign In / Providers desactiva *Allow new users to sign up*. Las cuentas las crean los gerentes desde la app.

Si la base ya tenía el Parcial 1 cargado, basta con los pasos 2 y 4.

## Cómo ejecutar

1. Abre `PumaStations.xcodeproj`.
2. Elige un simulador de iPhone y presiona **Run** (⌘R).
3. En un iPhone físico, elige tu equipo en *Signing & Capabilities*. Si Xcode lo pide, cambia el *Bundle Identifier*.

Sin Mac: el workflow `.github/workflows/ios-build.yml` compila la app en cada push a `main`.

### Cuentas de prueba

Todas usan la contraseña **`Puma2026`**.

| Rol | Correo | Qué verás |
|---|---|---|
| Gerente general | `gerente@puma.sv` | Dashboard consolidado, 2 alertas críticas |
| Gerente de sucursal | `rmartinez@puma.sv` | Puma Escalón: corte vespertino con 4 de 6 bombas |
| Gerente de sucursal | `chernandez@puma.sv` | Puma Soyapango: Súper en nivel crítico |
| Gerente de sucursal | `alopez@puma.sv` | Puma Santa Tecla: corte vespertino sin iniciar |
| Gerente sin sucursal | `gflores@puma.sv` | Pantalla de "sin sucursal" |
| Empleado (pistero) | `mrivas@puma.sv` | Puma Escalón: turno matutino con entrada marcada, puede vender |
| Empleado (cajera) | `scampos@puma.sv` | Puma Escalón: turno vespertino por marcar entrada |
| Empleado (mantenimiento) | `dmolina@puma.sv` | Puma Escalón: órdenes de mantenimiento |

Los días de descanso del ejemplo son domingo (pistero), lunes (cajera) y martes (mantenimiento): ese día la cuenta no tiene turno y el gerente puede asignarle uno desde **Personal → Turnos**.

## Cumplimiento del PDF

| Requisito | Dónde está |
|---|---|
| Login y navegación por rol | `RootView` elige `GeneralTabView` o `BranchTabView` según el rol |
| Métricas consolidadas de ventas y consumo por combustible | `GeneralDashboardView` y `DashboardCalculator` |
| Filtro país / sucursal (además de periodo y combustible) | `DashboardFilterSheet` |
| Registrar estaciones | `BranchFormView`, que crea las 6 bombas automáticamente |
| Alta de gerentes y vínculo con su sucursal | `ManagerFormView` |
| Vista detallada por estación | `StationDetailView` |
| 2 cortes diarios (matutino y vespertino) | `CutsHubView` y `CutService` |
| 3 categorías de movimiento: ventas, recepción, pérdidas o daños | `CutDetailView`, `PumpSaleView`, `ReceptionFormView` y `LossFormView` |
| 6 bombas por sucursal; el corte solo cierra con las 6 registradas | `BusinessRules.pumpsPerBranch` y `CutService.close` |
| Consolidación automática de los 6 registros | `CutReportView` (reporte e inventario del corte) |
| Dashboard de tanques con alertas crítico / medio / óptimo | `TankDashboardView`, `InventoryCalculator` y `TankStatus` |

### Parcial 2

| Requisito | Dónde está |
|---|---|
| Rol Empleado con su propia navegación | `RootView` → `EmployeeTabView` (Mi turno, Tienda, Mantenimiento, Perfil) |
| Gestión de empleados / personal | `StaffHubView` → `EmployeeListView` y `EmployeeFormView` (gerente de sucursal); el gerente general los consulta en `StationDetailView` |
| Control de turnos y horarios de trabajo | `ScheduleView` (horario semanal y asistencia) y `MyShiftView` (entrada y salida del empleado), con las reglas en `ShiftService` |
| Venta de productos de conveniencia y lubricantes | `SaleView` con `SaleKind.store`, `SaleService` y el inventario en `StoreInventoryView` |
| Otros servicios: mantenimiento | `SaleView` con `SaleKind.service`: revisión y cambio de aceite, anticongelante, líquido de frenos y aire para neumáticos |
| Catálogo y precios de la franquicia | `CatalogListView` y `CatalogItemFormView` (gerente general) |
| El gerente de sucursal ve las ventas de su sucursal | `BranchSalesView`: combustible, tienda y mantenimiento por periodo, más vendidos, ventas por empleado y últimas ventas |

## Arquitectura MVVM

```
PumaStations/
├── App/            Punto de entrada; RootView decide la vista según el rol
├── Core/           Colores de marca, estilos, formatos y utilidades
├── Models/         Modelos de SwiftData y enums del negocio
├── Services/       DataStore, sesión, reglas de cortes, inventario y métricas
│   └── Supabase/   Cliente REST/Auth, filas de cada tabla y cola de sincronización
├── ViewModels/     Un ViewModel @Observable por pantalla
│   ├── Auth/
│   ├── General/    Gerente general
│   ├── Branch/     Gerente de sucursal
│   └── Employee/   Empleado
└── Views/          Vistas SwiftUI, sin lógica de negocio
    ├── Components/ Tarjetas reutilizables (tanques, ventas, cortes, tienda)
    ├── General/
    ├── Branch/
    ├── Employee/
    └── Shared/
```

Qué hace cada capa:

- **Model:** modelos de SwiftData, que son la copia local de lo que el usuario puede ver en Supabase.
  - `Branch` tiene 6 `Pump` y sus `SalesCut`.
  - Cada `SalesCut` agrupa las tres categorías de movimiento: `PumpSale` (una por bomba), `FuelReception` y `FuelLoss`.
  - `UserAccount` guarda al usuario y su rol (gerente general, gerente de sucursal o empleado).
  - `WorkShift` es el turno de un empleado en un día, con sus marcas de entrada y salida.
  - `CatalogItem` es un producto o servicio del catálogo; `StockEntry` es una entrada de inventario de una sucursal.
  - `Sale` es una venta de tienda o una orden de mantenimiento, con sus líneas `SaleItem`.
- **ViewModel:** contiene el estado de la pantalla y sus validaciones.
  - Lee y guarda a través de `DataStore`, que sube cada cambio a Supabase.
  - Delega las reglas del negocio a los servicios.
- **View:** solo dibuja el estado del ViewModel y le envía las acciones del usuario. Cada vista crea su ViewModel con `@State` y le inyecta las dependencias por el `init`.
- **Services:** lógica pura y fácil de probar.
  - `CutService` controla el orden de los cortes, que no falte ninguna bomba y el cierre con actualización de tanques.
  - `InventoryCalculator` calcula niveles, promedio diario, días restantes y alertas.
  - `DashboardCalculator` consolida las métricas.
  - `ShiftService` asigna turnos y marca la asistencia.
  - `SaleService` valida y registra las ventas; `StoreCalculator` calcula existencias y métricas de tienda.

## Reglas del negocio

- **Cortes:**
  - Hay 2 cortes al día. El vespertino solo se puede iniciar cuando el matutino está cerrado.
  - Un corte se cierra únicamente con los registros de las 6 bombas. Si una bomba no despachó, se marca como *fuera de servicio* y cuenta como registrada.
- **Inventario:**
  - Al cerrar un corte, cada tanque se actualiza así: existencia + recepciones − ventas − pérdidas.
  - No se permite que un tanque quede negativo ni que supere su capacidad.
  - Un corte cerrado queda bloqueado.
- **Alertas:** se calculan con el nivel del tanque y los días de venta que le quedan, según el promedio de los últimos 7 días.
  - **Crítico:** menos del 20 % o menos de 1.5 días.
  - **Medio:** menos del 40 % o menos de 3 días.
  - **Óptimo:** el resto.
  - La app sugiere cuánto pedir para llevar el tanque al 85 %.
- **Métricas:** solo cuentan los cortes cerrados.
  - Ventas y galones por combustible.
  - Compras recibidas.
  - Pérdidas en galones y su valor a costo.
  - Margen bruto: ventas − compras − pérdidas.
- **Personal y turnos:**
  - El gerente de sucursal da de alta a los empleados de su estación; el gerente general solo los consulta.
  - Cada día tiene los mismos dos turnos que los cortes: matutino (6:00 a. m. – 2:00 p. m.) y vespertino (2:00 – 10:00 p. m.).
  - Un empleado tiene como máximo un registro por día y turno, y no se asignan turnos en días pasados.
  - El empleado marca entrada y salida solo en su turno de hoy. Un turno con asistencia ya no se puede quitar.
- **Tienda y mantenimiento:**
  - El catálogo y los precios son de la franquicia: los define el gerente general y aplican a todas las sucursales.
  - Cada sucursal lleva su inventario: existencia = entradas − unidades vendidas. No se guarda un contador que pueda desfasarse.
  - Un producto está **agotado** sin existencia y **bajo** cuando llega al mínimo del catálogo. Los servicios no llevan inventario.
  - Solo vende un empleado con la entrada de su turno marcada. No se puede vender más de lo que hay en existencia.
  - Una orden de mantenimiento pide la placa del vehículo y cobra cada servicio una vez.
  - La venta copia el precio del momento, así que cambiar el catálogo no altera ventas pasadas. Las ventas no se editan ni se borran.
- **Alcance por rol:** el gerente de sucursal y el empleado solo ven datos de su propia estación, y cada estación tiene un solo gerente.
- **Contraseñas:** las guarda Supabase Auth; la app nunca las almacena.

## Conexión con Supabase

- **Inicio de sesión:** `SupabaseClient.signIn` usa Supabase Auth (correo y contraseña). Después `RemoteSync.signIn` descarga las tablas y `DataStore` reemplaza la copia local.
- **Escrituras:** `DataStore.save()` guarda en SwiftData y encola los cambios (`SyncOperation`); `RemoteSync` los sube en orden. Si una subida falla, la app muestra una alerta para reintentar o cerrar sesión.
- **Seguridad (RLS):** el gerente general ve todo; el gerente de sucursal y el empleado solo su estación. Un corte cerrado queda bloqueado también en el servidor.
  - El empleado no ve cortes ni tanques: solo el catálogo, el inventario y las ventas de su tienda, y sus propios turnos.
  - El servidor también rechaza una venta sin existencias y que un empleado cambie el día de su turno.
- **Gerentes:** se crean y editan con la función `save_manager`, que solo acepta al gerente general.
- **Empleados:** se crean y editan con la función `save_employee`, que solo acepta al gerente de sucursal y siempre los asigna a su estación.
- Los datos se descargan al iniciar sesión: para ver cambios hechos desde otro dispositivo hay que volver a entrar.

## Logo

El logo de Puma Energy está en `Assets.xcassets/PumaLogo.imageset` y se muestra en `LoginView`.
