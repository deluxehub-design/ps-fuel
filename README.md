# PS Fuel 3.5.1 — Multi-Fuel, Aviation & Biofuel Update & Tablet UI instead of full screen

PS Fuel 3.5.1 is a physical multi-fuel and EV energy system for FiveM. It keeps the existing 0–100 fuel compatibility interface used by JG, TGIANN, garage and HUD scripts while adding real tank volume, fuel quality, fleet billing, vehicle wear, station operations, EV battery health and secured fuel-transfer gameplay.

Repository: `deluxehub-evolvenetwork/ps-fuel`

## Core support

Framework bridge modes:

- Qbox
- QBCore
- ESX Legacy
- Standalone / vMenu
- Custom framework adapter

Required resources:

```cfg
ensure ox_lib
ensure oxmysql
ensure ox_target
ensure ps-fuel
```

OneSync is required. Do not run another resource that provides `ps-fuel`, `cdn-fuel` or `LegacyFuel` at the same time.


## 3.5.0 multi-fuel expansion

3.5.0 expands the fuel-quality system into multiple fuel families while preserving the normal 0–100 compatibility exports used by JG, TGIANN and custom vehicle scripts.

**Petrol / Benzin:** Regular 87, Midgrade 89, Premium 91, Premium 93, Premium 98, Benzin 95, Benzin 98 and Race Fuel 100.

**Ethanol and biofuel:** E10, E15, E85 Bioethanol and E100 Bioethanol. E85/E100 require flex-fuel support when contamination gameplay is enabled.

**Diesel and renewable fuel:** Diesel, Premium Diesel, ULSD, B5/B20/B100 biodiesel, HVO100, Renewable Diesel R99 and Marine Diesel.

**Aviation:** Avgas 100LL, Avgas UL94, Jet A, Jet A-1, SAF 50, SAF 100 and JP-8-style turbine fuel.

**Special:** Methanol M100, Nitromethane Race Fuel, RP-1-style Rocket Kerosene and a generic gameplay Rocket Propellant. These are only valid for vehicle models configured to the matching fuel family.

Fuel compatibility is based on the vehicle's fuel family. Wrong-family fuel contributes to contamination when contamination gameplay is enabled. Fuel grades can define a consumption multiplier so lower-energy-density fuels use more volume without changing the existing percentage-based HUD/garage API.

Piston aircraft listed in `PSFuelConfig.VehicleFuelFamilyModels` automatically use Avgas. Other GTA helicopter/plane classes default to Jet/Turbine fuel. Admins can override any model using `/fuelvehicleconfig`.

## 3.4.0 highlights

### Fuel grades and fuel quality

PS Fuel supports multiple liquid fuel grades rather than treating every pump as one generic petrol value.

Default grades include:

- Regular petrol — 87 octane
- Midgrade — 89 octane
- Premium — 91 octane
- Premium 93 — 93 octane
- E85
- Diesel
- Premium diesel
- Electric charging

Vehicles can have a recommended octane. Running lower octane can increase consumption and reduce performance. E85 can require a flex-fuel vehicle. Wrong-family fuel can create a persistent contamination percentage.

Contamination can be configured to cause:

- Reduced engine output
- Rough running
- Random stalling
- Increased fuel consumption
- Required dilution or mechanic intervention

Harsh wrong-fuel effects can be disabled in `PSFuelConfig.Advanced.FuelQuality`.

### Real tank capacity

Vehicle fuel is still exposed as 0–100 percent through compatibility exports, but internally PS Fuel converts that percentage to a real physical capacity.

Tank capacity can be configured by:

- Vehicle model
- Vehicle class
- Electric vehicle profile
- Truck profile
- Dual-tank profile

This allows displays such as:

```text
137.4 / 300 L
```

or the configured regional unit equivalent.

### Economy, range and trip computer

Consumption takes account of:

- Vehicle class
- RPM
- Throttle
- Road speed
- Engine upgrades
- Fuel-system wear
- Fuel octane
- Contamination
- Weather
- Engine idling

The `/fueltrip` trip computer exposes:

- Current fuel/energy
- Estimated range
- Current economy
- Trip distance
- Trip fuel used
- Trip cost
- Idle fuel used
- EV battery health
- Trip reset

Supported economy formats include L/100 km, UK MPG and US MPG.

### Truck fuel system

Heavy vehicles can use:

- Larger tank capacities
- Main and secondary tanks
- Diesel-only profiles
- Higher realistic consumption
- Higher idle consumption
- High-flow commercial diesel pumps
- Fleet/company payment
- Persistent tanker cargo

This is designed to work alongside LS Trucker and other trucking resources without changing the normal `GetFuel` / `SetFuel` API.

### Fleet accounts and fuel cards

Businesses and departments can use persistent fleet accounts and metadata-backed `ps_fuel_card` items.

A fleet card can contain:

- Company/account ID
- Assigned driver
- Daily spending limit
- Allowed fuel types
- Allowed stations
- Transaction usage

Create an account from server code:

```lua
exports['ps-fuel']:CreateFleetAccount('croft-logistics', 'Croft Logistics', 50000, 5000, 'trucker')
```

Administrative card issuing command:

```text
/fuelcardissue [server id] [account id] [daily limit] [optional PIN]
```

When `PSFuelConfig.Advanced.Fleet.AutoUseFuelCard` is enabled, a valid fleet card can automatically pay before the player's personal account is charged.

### Loyalty system

Fuel purchases can generate persistent loyalty points. Configurable tiers can provide percentage discounts such as Bronze, Silver, Gold and Platinum.

### Wholesale market and suppliers

Player-owned stations can operate against a changing wholesale fuel multiplier.

FuelOS supports configurable supplier contracts with:

- Wholesale multiplier
- Delivery time
- Reliability
- Minimum order

Owners/employees can select suppliers and order NPC restocks. Delivery costs are included in station analytics.

### Station employees and upgrades

FuelOS supports persistent station employees and configurable roles/permissions.

Station upgrade categories include:

- Storage
- Pumps
- Chargers
- Security
- Tanker/delivery capacity

Upgrades can affect storage size, pump/charger speed, robbery protection and delivery quantities.

### Station maintenance

Fuel station equipment wears as fuel is sold. Poor condition can reduce effective station performance. Owners can pay for maintenance from the station balance.

### Station analytics

FuelOS exposes station analytics including:

- Fuel volume sold
- Revenue
- Average transaction
- Fuel type breakdown
- EV charging revenue
- Wholesale multiplier
- Maintenance condition
- Delivery costs
- Robbery losses
- Employees
- Supplier
- Upgrade levels

### Price boards

Configured stations can display live fuel prices in the world. Price boards update when station pricing or the wholesale market changes.

### Fuel theft and siphoning

`/siphonfuel [litres]` uses a `siphon_hose` and a short skill check.

The server validates:

- Player distance
- Vehicle entity
- Siphon hose ownership
- Requested quantity
- Available fuel
- Maximum siphon quantity

Successful siphoning creates a metadata-backed portable fuel container and can trigger a police dispatch event.

### Portable fuel containers

Default portable containers:

- `fuel_can_5l`
- `fuel_can_10l`
- `fuel_can_20l`
- `diesel_can_20l`

The amount inside the can is stored in item metadata. A container can move fuel between itself and a vehicle while respecting both capacities.

### Vehicle-to-vehicle fuel transfer

`/fueltransfer [litres]` transfers fuel between two nearby vehicles. Distance, source quantity, target capacity and transfer amount are validated server-side.

### Tanker cargo and mobile refuelling

Supported tanker/service vehicles can hold persistent fuel cargo by plate.

Exports:

```lua
local cargo = exports['ps-fuel']:GetTankerCargo(plate)
exports['ps-fuel']:SetTankerCargo(plate, 'diesel', 12000, 30000)
```

`/mobilefuel [litres]` can refuel a stranded nearby vehicle from supported service-vehicle cargo.

### Drive-offs and post-pay fuel

Post-pay mode allows a station to record a pending transaction before settlement. Leaving without paying can:

- Reverse station revenue
- Record robbery/drive-off losses
- Create a theft transaction
- Trigger dispatch
- Trigger an optional CCTV integration event

Use `/fuelpostpay` to toggle post-pay behaviour when the feature is enabled.

### Pump damage and fuel spills

Driving away with an attached nozzle can:

- Tear the hose from the pump
- Create a synchronized fuel spill
- Damage station equipment
- Generate a station repair cost
- Create a small configurable fire risk

Spills are persistent for their configured lifetime and can affect players moving through them.

### Fuel-system wear and mechanic repairs

Per-plate fuel-system state tracks:

- Fuel filter
- Fuel pump
- Injectors
- Fuel tank
- EV battery
- Charging port

Poor filter/injector condition increases consumption. A badly worn pump can cause intermittent stalls. Severe tank wear can create a persistent fuel leak.

Default repair items:

- `fuel_filter`
- `fuel_pump`
- `fuel_injectors`
- `fuel_tank`
- `ev_battery_module`
- `charging_port`

Mechanic repair item use is server-authorised and uses a skill/progress sequence before consuming the replacement part.

JG Mechanic or another mechanic system can also integrate through:

```lua
local state = exports['ps-fuel']:GetVehicleEnergyState(plate)
exports['ps-fuel']:RepairFuelSystemPart(plate, 'filter', 100)
exports['ps-fuel']:RepairFuelSystemPart(plate, 'pump', 100)
exports['ps-fuel']:RepairFuelSystemPart(plate, 'injectors', 100)
exports['ps-fuel']:RepairFuelSystemPart(plate, 'tank', 100)
exports['ps-fuel']:RepairFuelSystemPart(plate, 'battery', 20)
exports['ps-fuel']:RepairFuelSystemPart(plate, 'charging_port', 100)
```

### Fuel leak repair item and minigame

Normal leak repair no longer relies on `/repairfuelleak`.

Use the inventory item:

```text
fuel_repair_kit
```

The repair flow validates the item, vehicle, distance and persisted leak state on the server. The client then completes an ox_lib skill check and progress interaction. The kit is consumed only after a successful server re-validation.

Normal and severe leaks can use different minigame difficulty and repair duration.

The old chat command is disabled by default in 3.4.0.

### EV battery health and charging curve

Electric vehicles maintain persistent battery health by plate. Battery degradation reduces usable range.

Fast and standard charging can taper after 80% charge. Charger occupancy prevents two vehicles from owning the same charging connector at the same time.

When enabled, a completed vehicle can accrue charger idle fees until the connector/session is released.

Cold/snow weather reduces EV range.

### Home chargers and private/business pumps

External property/business resources can register private energy points:

```lua
exports['ps-fuel']:RegisterPrivateEnergyPoint({
    ownerIdentifier = 'license:example',
    pointType = 'home_charger',
    label = 'Home Charger',
    coords = vec3(100.0, 200.0, 30.0),
    auth = {
        jobs = { police = 0 },
        plates = { 'ABC123' },
        ace = 'ps-fuel.private'
    }
})
```

Private points can be restricted by job/grade, plate, owner and ACE permission.

### Roadside assistance hooks

Players can use:

```text
/roadsidefuel
```

The command emits the configured roadside dispatch event. Phone, CAD and dispatch resources can listen for or trigger the same integration.

### Physical fuel caps and nozzle rules

The nozzle system prefers vehicle fuel-cap/tank bones when available and supports per-model offsets for unusual/modded vehicles.

Nozzle/fuel-family rules distinguish:

- Petrol
- Diesel
- EV connector
- High-flow commercial diesel

### Regional units

Configuration supports:

- Litres
- Gallons
- Currency per litre/gallon
- L/100 km
- UK MPG
- US MPG

The compatibility API remains percentage-based regardless of display units.

### Weather and idle consumption

Snow/cold weather affects EV range and increases ICE consumption slightly. Rain also applies a smaller consumption penalty. Vehicles consume fuel while idling with the engine running, with a higher configurable idle rate for trucks.

### Vehicle fuel history

Every completed purchase can be stored against the vehicle plate with:

- Station
- Fuel type
- Volume
- Amount paid
- Odometer
- Time

Use `/fuelhistory` while near/in a vehicle to view recent records.

## Compatibility exports

Existing integrations remain supported:

```lua
local fuel = exports['ps-fuel']:GetFuel(vehicle)
exports['ps-fuel']:SetFuel(vehicle, 100.0)
exports['ps-fuel']:AddFuel(vehicle, 10.0)
exports['ps-fuel']:RemoveFuel(vehicle, 5.0)

local sameFuel = exports['ps-fuel']:getFuel(vehicle)
exports['ps-fuel']:setFuel(vehicle, 75.0)
```

New vehicle-energy exports:

```lua
local fuelType = exports['ps-fuel']:GetFuelType(vehicle)
local capacity = exports['ps-fuel']:GetFuelCapacity(vehicle)
local rangeKm = exports['ps-fuel']:GetFuelRange(vehicle)
local economy, unit = exports['ps-fuel']:GetFuelEconomy(vehicle)
local battery = exports['ps-fuel']:GetEVBatteryHealth(vehicle)
local leaking = exports['ps-fuel']:IsFuelLeaking(vehicle)
local tanks = exports['ps-fuel']:GetFuelTankSplit(vehicle)
local fuelCap = exports['ps-fuel']:GetFuelCapPosition(vehicle)
```

The existing native fuel level, `_FUEL_LEVEL`, generic `fuel` statebag and `recoilFuel` statebag synchronization remains available for TGIANN, JG and custom resources.

## Developer events

3.4.0 exposes gameplay events for integrations:

```text
ps-fuel:fuelStarted
ps-fuel:fuelStopped
ps-fuel:fuelChanged
ps-fuel:vehicleEmpty
ps-fuel:vehicleRefuelled
ps-fuel:stationStockChanged
ps-fuel:paymentCompleted
ps-fuel:fuelPurchased
ps-fuel:fuelLeakStarted
ps-fuel:fuelLeakRepaired
ps-fuel:fuelTheft
ps-fuel:roadsideRequested
```

## Security

The server validates sensitive fuel operations rather than accepting client totals blindly.

Validation includes:

- Refuelling distance
- Vehicle/session entity
- Fuel type
- Maximum physical amount per tick
- Station stock
- Payment
- Fleet account/card limits
- Portable container capacity
- Siphoning inventory and quantity
- Vehicle-to-vehicle transfer distance/capacity
- Leak repair session/item/distance/state
- Mechanic replacement part sessions
- Private energy point authorization

Suspicious operations can be written to the normal audit system and optionally Discord.

## Discord logging

Enable `PSFuelConfig.Advanced.Discord` and configure the webhook to log configured events such as:

- Fuel purchases
- Station withdrawals
- Robberies
- Administrative changes
- Suspicious fuel activity

## Inventory items

Ready-to-copy item definitions are included in:

```text
install/items/tgiann-inventory.lua
install/items/qbox-items.lua
```

Add the definitions to the inventory resource you actually use. Existing common images such as `repairkit.png`, `jerry_can.png` and `bank_card.png` are referenced where possible.

## Database

All `ps_fuel_*` tables are automatically created/upgraded at startup. No manual import is required for a normal install.

A current manual schema is still included at:

```text
install/ps-fuel.sql
```

3.4.0 adds persistent tables for vehicle energy/wear/history, fleet accounts/cards, loyalty, station employees/advanced state, tanker cargo, private points and spills.

## Useful commands

```text
/fuel
/fuelstation
/fueladmin
/fuelvehicleconfig
/setfuel 100
/fueltrip
/fueltripreset
/fuelhistory
/fuelpostpay
/fuelloyaltycard
/fuelcardpin [PIN]
/siphonfuel [litres]
/fueltransfer [litres]
/mobilefuel [litres]
/roadsidefuel
/closefuel
/psfuelversion                 server console
```

# PS Fuel 3.5.1 — Unified Tablet UI

This maintenance release moves every interactive menu and form into the FuelOS tablet shell. It also removes the fullscreen CSS override that hid the tablet frame and centralizes tablet focus/cancel handling.

Gameplay skill checks, progress circles, notifications and world interaction prompts remain lightweight in-world interfaces.

Administrative fleet commands:

```text
/fuelfleetcreate ...
/fuelcardissue [server id] [account id] [daily limit] [optional PIN]
```

## Version checker

The installed version is read from `fxmanifest.lua`:

```lua
version '3.5.1'
```

`version.lua` checks the latest GitHub release from:

```text
deluxehub-evolvenetwork/ps-fuel
```

It runs shortly after resource startup and then every six hours. From the server console:

```text
psfuelversion
```

An unavailable GitHub API never prevents the resource from starting.

## JG, TGIANN and custom resources

JG HUD, JG Advanced Garages and other resources that support `ps-fuel` should continue to use their normal `ps-fuel` integration. They still receive the expected percentage fuel value.

TGIANN/custom resources that write GTA fuel natives, `_FUEL_LEVEL`, `fuel` or `recoilFuel` continue to synchronize with PS Fuel.

For new code, prefer PS Fuel exports because they update the cache, statebags and empty-engine state together.

## Upgrade from 3.3.0

1. Back up the existing resource and database.
2. Replace the resource with 3.5.1.
3. Merge your custom station/model configuration into the new `config.lua`.
4. Add the new inventory items from `install/items`.
5. Confirm `ox_lib`, `oxmysql` and `ox_target` start before PS Fuel.
6. Start your framework/inventory before PS Fuel when its usable-item API is required.
7. Perform a full server restart.
8. Run the tests in `TESTING.md` before production use.

## License

The project retains the licence notices included in the resource. Imported GPL-covered donor code/assets continue to be distributed under their applicable GPL terms.


## 3.5.1 unified tablet interface

All interactive PS Fuel menus now use the built-in FuelOS tablet shell. Fuel selection, payment, station ownership and management, employees, trip computer, fuel history, portable fuel transfer, private/home energy points, and vehicle fuel configuration use the same NUI design and focus lifecycle. ox_lib remains in use for gameplay skill checks, progress circles, notifications, and world interaction hints.
