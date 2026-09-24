# PS Fuel v3.5.0

## Added
- Added expanded petrol octanes and grades: 87, 89, 91, 93, 98, Benzin 95/98 and Race Fuel 100.
- Added E10, E15, E85 and E100 ethanol/bioethanol fuels.
- Added ULSD, B5/B20/B100 biodiesel, HVO100, Renewable Diesel R99 and Marine Diesel.
- Added Avgas 100LL, Avgas UL94, Jet A, Jet A-1, SAF 50, SAF 100 and JP-8-style aviation fuel.
- Added Methanol M100, Nitromethane Race Fuel, RP-1-style Rocket Kerosene and gameplay Rocket Propellant.
- Added configurable vehicle fuel families and automatic aircraft family detection.
- Added per-grade consumption multipliers and configurable multi-grade price boards.

## Changed
- `/fuelvehicleconfig` now supports petrol, diesel, Avgas, Jet/Turbine, Methanol, Nitromethane, Rocket and Electric families.
- Compatibility checks now use the vehicle fuel family instead of assuming all non-diesel vehicles use petrol.
- Version checker now reports installed version 3.5.0 through `fxmanifest.lua`.

---

# PS Fuel v3.4.0

Vehicle Energy, Fleet & Station Operations update.

## Hotfix — server vehicle class resolution

- Fixed `server/advanced.lua` calling the client-only `GetVehicleClass` native on the FXServer.
- Added a validated client-reported/statebag vehicle-class bridge for advanced fuel callbacks.
- Fixed advanced vehicle state, siphoning, vehicle-to-vehicle transfer, portable cans, mobile refuelling and private energy points using vehicle classes server-side.
- Preserved model/class-specific tank capacities without spamming server callback errors.

## Added

- Octane and fuel-quality system with 87/89/91/93, E85 and diesel grades.
- Persistent wrong-fuel contamination and dilution/recovery behaviour.
- Configurable real tank capacities by model/class.
- Truck dual-tank support and high-flow diesel behaviour.
- Realistic economy calculations, range estimation and trip computer.
- Weather and engine-idle consumption effects.
- Persistent fuel history by plate.
- Fleet accounts and metadata-backed company fuel cards.
- Loyalty points, tiers and fuel discounts.
- Wholesale fuel market and supplier contracts.
- NPC station restocking.
- Persistent tanker cargo and mobile refuelling.
- Server-authorised fuel siphoning and vehicle-to-vehicle transfers.
- Metadata-backed 5L/10L/20L petrol and diesel containers.
- Post-pay fuel and station drive-off handling.
- Pump damage and synchronized fuel spills.
- Persistent fuel filter, pump, injector, tank, EV battery and charging-port condition.
- Mechanic fuel-system replacement items and JG/custom repair exports.
- EV battery degradation and charge-rate taper above configured state-of-charge.
- Charger occupancy and EV idle-fee support.
- Private/home chargers and restricted business/department pumps.
- Job/grade/plate/owner/ACE authorization for private points.
- Roadside assistance integration event and command.
- FuelOS station analytics, employees, supplier controls, upgrades and maintenance.
- Live station price boards.
- Discord logging hooks.
- New HUD/developer exports and events.
- Dedicated `version.lua` checker for GitHub releases.
- TGIANN Inventory/QBox item install snippets.

## Leak repair

- Normal leak repair now uses `fuel_repair_kit` rather than a player chat command.
- Added normal/severe ox_lib skill checks and progress interaction.
- Server re-validates item, vehicle, distance and persistent leak state before repair.
- Repair kit is consumed only after a successful repair.
- Old leak repair command is disabled by default.

## Security

- Added physical-volume anti-cheat validation to refuelling.
- Siphoning is validated before fuel is removed.
- Vehicle-to-vehicle transfers are server-approved.
- Portable container quantities/capacities are server-controlled.
- Private pump/charger authorization is server-controlled.
- Mechanic/leak repair use short-lived server repair sessions.

## Compatibility

- `GetFuel` / `SetFuel` remain percentage based.
- Lowercase aliases remain available.
- `AddFuel` / `RemoveFuel` remain available.
- GTA native, `_FUEL_LEVEL`, `fuel` and `recoilFuel` synchronization remains supported.
- Existing JG/TGIANN/custom integrations do not need to understand litres/kWh to keep working.

# PS Fuel v3.3.0

Universal framework release with Qbox, QBCore, ESX, standalone/vMenu and custom framework bridge support.
