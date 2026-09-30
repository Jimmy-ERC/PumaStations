# Puma Estaciones: gestión de franquicia de gasolineras (SwiftUI + MVVM)

App nativa para iPhone de la franquicia de estaciones **Puma Energy** en El Salvador. Maneja tres combustibles: Súper, Regular y Diésel. Sigue las indicaciones del documento *LABORATORIO 22* y el diseño v2 de Figma.

## Requisitos

- Xcode 16 o superior (preparado para Xcode 16.4).
- iOS 17.0 o superior (simulador o iPhone).
- Sin dependencias externas: usa SwiftUI, SwiftData, Swift Charts y CryptoKit.

## Cómo ejecutar

1. Abre `PumaStations.xcodeproj`.
2. Elige un simulador de iPhone y presiona **Run** (⌘R).
3. En un iPhone físico, elige tu equipo en *Signing & Capabilities*. Si Xcode lo pide, cambia el *Bundle Identifier*.

La primera vez que se abre, la app carga datos de ejemplo: 3 estaciones operando con 45 días de cortes, y 1 estación sin gerente. Si antes instalaste la versión anterior de la app, sus datos se borran y se cargan los nuevos automáticamente.

### Cuentas de prueba

Todas usan la contraseña **`Puma2026`**.

| Rol | Correo | Qué verás |
|---|---|---|
| Gerente general | `gerente@puma.sv` | Dashboard consolidado, 2 alertas críticas |
| Gerente de sucursal | `rmartinez@puma.sv` | Puma Escalón: corte vespertino con 4 de 6 bombas |
| Gerente de sucursal | `chernandez@puma.sv` | Puma Soyapango: Súper en nivel crítico |
| Gerente de sucursal | `alopez@puma.sv` | Puma Santa Tecla: corte vespertino sin iniciar |
| Gerente sin sucursal | `gflores@puma.sv` | Pantalla de "sin sucursal" |

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
| Fuera de alcance (Parcial 2): empleados, turnos y otros servicios | No incluidos |

## Arquitectura MVVM

```
PumaStations/
├── App/            Punto de entrada; RootView decide la vista según el rol
├── Core/           Colores de marca, estilos, formatos y utilidades
├── Models/         Modelos de SwiftData y enums del negocio
├── Services/       DataStore, sesión, reglas de cortes, inventario, métricas y datos de ejemplo
├── ViewModels/     Un ViewModel @Observable por pantalla
│   ├── Auth/
│   ├── General/    Gerente general
│   └── Branch/     Gerente de sucursal
└── Views/          Vistas SwiftUI, sin lógica de negocio
    ├── Components/ Tarjetas reutilizables (tanques, ventas, cortes)
    ├── General/
    ├── Branch/
    └── Shared/
```

Qué hace cada capa:

- **Model:** guarda los datos en SwiftData.
  - `Branch` tiene 6 `Pump` y sus `SalesCut`.
  - Cada `SalesCut` agrupa las tres categorías de movimiento: `PumpSale` (una por bomba), `FuelReception` y `FuelLoss`.
  - `UserAccount` guarda al usuario y su rol.
- **ViewModel:** contiene el estado de la pantalla y sus validaciones.
  - Lee y guarda a través de `DataStore`.
  - Delega las reglas del negocio a los servicios.
- **View:** solo dibuja el estado del ViewModel y le envía las acciones del usuario. Cada vista crea su ViewModel con `@State` y le inyecta las dependencias por el `init`.
- **Services:** lógica pura y fácil de probar.
  - `CutService` controla el orden de los cortes, que no falte ninguna bomba y el cierre con actualización de tanques.
  - `InventoryCalculator` calcula niveles, promedio diario, días restantes y alertas.
  - `DashboardCalculator` consolida las métricas.

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
- **Alcance por rol:** el gerente de sucursal solo ve y registra datos de su propia estación, y cada estación tiene un solo gerente.
- **Contraseñas:** se guardan como hash SHA-256.

## Logo

El logo de Puma Energy está en `Assets.xcassets/PumaLogo.imageset` y se muestra en `LoginView`.
