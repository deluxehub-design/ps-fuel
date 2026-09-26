# PS Fuel 3.5.2 — Fuel Category Auto-Detection

This build changes the pump/refuelling flow so a vehicle only sees fuel types that belong to its detected category.

## Automatic categories

- **Road Petrol** — normal petrol vehicles.
- **Flex Fuel / Ethanol** — only models listed in `Advanced.FuelQuality.FlexFuelModels`, in addition to normal road petrol.
- **Road Diesel** — diesel models and configured diesel vehicle classes.
- **Racing / Drag Fuel** — automatically added to GTA vehicle classes **4 (Muscle), 6 (Sports), and 7 (Super)**, plus any model added to `VehicleCategoryDetection.RacingModels`.
- **Piston Aviation Fuel** — aircraft models explicitly configured as `avgas`.
- **Jet / Turbine Fuel** — other aircraft/turbine vehicles.
- **Electric Charging** — configured EV models only.

`Race Fuel 100`, `Methanol`, `Nitromethane`, `RP-1 Rocket Kerosene`, and `Rocket Propellant` are in the **Racing / Drag Fuel** category. Rocket fuel is no longer automatically tied to the Thruster; the Thruster is treated as turbine/jet powered.

## UI and server enforcement

The NUI now renders only compatible fuel choices instead of rendering every fuel and disabling the incompatible entries. The server also independently validates the detected category during purchases, so a modified NUI cannot buy an incompatible category by default.

Set `PSFuelConfig.VehicleCategoryDetection.AllowWrongCategoryFuel = true` only if you intentionally want the old wrong-fuel/contamination behaviour to permit cross-category selection.

## Custom race / drag vehicles

Add models here in `config.lua` when a custom drag vehicle is not GTA class 4, 6, or 7:

```lua
PSFuelConfig.VehicleCategoryDetection.RacingModels = {
    [`my_drag_car`] = true,
}
```

## Electric charging + battery health

EV charging now increases the normal 0–100 charge level and restores stored EV battery health during the same charging session.

```lua
PSFuelConfig.Advanced.EV.ChargingRestoresBatteryHealth = true
PSFuelConfig.Advanced.EV.BatteryHealthRestorePerChargePercent = 1.0
```

At the default `1.0`, each 1% charge purchased restores 1 battery-health point, capped at 100%. The advanced vehicle state is refreshed once charging completes so battery-health exports/UI receive the new value immediately.
