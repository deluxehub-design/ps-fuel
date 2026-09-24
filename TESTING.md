# PS Fuel 3.5.0 staging checklist

Run this on a staging server before production.

## Startup

- Confirm no Lua/NUI errors on resource start.
- Confirm all `ps_fuel_*` tables are created automatically.
- Run `psfuelversion` from server console and confirm installed version reports 3.4.0.

## Compatibility

- Verify JG HUD reads fuel normally.
- Store/retrieve a vehicle through the active garage and confirm fuel persists.
- If using TGIANN Inventory, use a `fuel_repair_kit` and portable fuel can.
- Verify `_FUEL_LEVEL`, `fuel` and `recoilFuel` stay synchronized after an external fuel write.

## Liquid fuel

- Refuel Regular, Midgrade, Premium, Premium 93, E85 and diesel vehicles.
- Verify litres/gallons and tank capacity display correctly.
- Verify high-flow diesel is faster for configured trucks.
- Intentionally put wrong fuel in a test vehicle and verify contamination/performance behaviour.
- Add correct fuel and verify configured dilution recovery.

## Trip computer

- Drive at different RPM/throttle levels and compare economy.
- Leave the engine idling and confirm idle fuel use increases.
- Test snow/rain weather effects.
- Run `/fueltrip` and verify range, economy, trip distance, fuel and cost.
- Reset the trip and confirm persistent counters reset.

## Fleet

- Create a fleet account.
- Issue a fuel card.
- Confirm metadata is present.
- Test daily limits, fuel restrictions and station restrictions.
- Confirm valid fleet purchases use the fleet account rather than player money.

## Stations

- Change retail price and verify price board updates.
- Change supplier and place NPC delivery order.
- Add/remove station employee.
- Buy each station upgrade type.
- Sell enough fuel to reduce station maintenance, then repair it.
- Confirm analytics update after fuel/EV purchases, robberies and deliveries.

## Theft and transfer

- Siphon a vehicle with and without `siphon_hose`.
- Confirm fuel is not removed when the server rejects the attempt.
- Test portable can fill/pour in both directions.
- Test vehicle-to-vehicle transfer at valid and invalid distance.
- Test post-pay drive-off and dispatch hook.

## Leaks and mechanic wear

- Create a normal and severe leak.
- Confirm there is no normal `/repairfuelleak` gameplay command.
- Use `fuel_repair_kit`; fail and pass the minigame.
- Confirm failed repair does not consume the kit.
- Confirm successful repair clears the persisted leak and consumes one kit.
- Reduce fuel pump condition and verify intermittent stall behaviour.
- Reduce tank condition and verify worn tank can create a leak.
- Use mechanic replacement items and verify condition restores.

## EV

- Charge below 80% and above 80%; verify taper.
- Test standard and fast charging.
- Test two players trying to use the same charger.
- Reach full charge and verify idle fee handling while the charger session remains occupied.
- Reduce battery health and verify range reduction.
- Test snow/cold range penalty.

## Pump/spill

- Drive away with a nozzle attached.
- Confirm hose returns/detaches, spill appears and station damage event records.
- Confirm spill expires.

## Private points

- Register a home charger/private pump through the export.
- Verify job/grade/plate/ACE restrictions.
- Verify unauthorized players cannot purchase fuel.

## Security

- Attempt oversized refuel/transfer values from a test client event.
- Attempt siphoning without the required item.
- Attempt leak repair completion without a valid session.
- Confirm each is rejected server-side.

## 3.5.0 fuel-family checks
- Petrol vehicle receives petrol/Benzin/ethanol grades and not Jet/Rocket grades.
- Diesel vehicle receives diesel/biodiesel/HVO grades.
- Duster/Mammatus/Cuban800/Velum family vehicles auto-detect as Avgas.
- Other helicopter/plane classes default to Jet/Turbine fuel.
- A vehicle configured as Rocket only receives RP-1/Rocket Propellant grades.
- E85/E100 on a non-flex-fuel petrol vehicle follows the contamination configuration.
- `/fuelvehicleconfig` lists every configured fuel family.
- Price board renders `PSFuelConfig.Advanced.PriceBoards.FuelTypes`.
- `GetFuel` and `SetFuel` remain 0-100 percentage compatible.
