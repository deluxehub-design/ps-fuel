# PS Fuel 3.5.2 — Vehicle Fuel Category Auto-Detection

PS Fuel 3.5.2 introduces category-aware refuelling. The resource detects the vehicle's compatible energy/fuel family before the pump UI is built, so players only see fuels that make sense for the vehicle they are using.

## Added

- Automatic categories for Road Petrol, Flex Fuel / Ethanol, Road Diesel, Racing / Drag Fuel, Piston Aviation Fuel, Jet / Turbine Fuel and Electric Charging.
- Configurable custom racing/drag model overrides through `PSFuelConfig.VehicleCategoryDetection.RacingModels`.
- Racing/drag category support for GTA vehicle classes 4 (Muscle), 6 (Sports) and 7 (Super).
- Server-side validation of the detected fuel category.
- Optional EV charging behaviour that restores persistent EV battery health while charging the vehicle.

## Racing / drag fuels

The racing/drag category includes Race Fuel 100, Methanol, Nitromethane, RP-1 Rocket Kerosene and Rocket Propellant. Rocket fuel is intended for configured racing/drag applications rather than being shown globally.

## Electric vehicles

Electric vehicles only receive the charging category by default. During a charging session, the normal EV charge level is increased and, when `ChargingRestoresBatteryHealth` is enabled, persistent EV battery health is restored at the configured rate and capped at 100%.

## Compatibility

The resource remains versioned as `ps-fuel` and retains the normal 0–100 fuel compatibility interface expected by supported HUD, garage and framework integrations.
