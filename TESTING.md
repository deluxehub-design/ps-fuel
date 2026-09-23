# PS Fuel 3.2.0 Production Test Checklist

## Startup

- Start `ox_lib`, `oxmysql` and `ox_target` first. If using Qbox, QBCore or ESX, start that framework before `ps-fuel`.
- Confirm `[ps-fuel] Database ready. Standalone fuel system active.` appears.
- Confirm `ps_fuel_vehicle_profiles` is created automatically.
- Confirm no missing NUI, electric model or callback errors appear.
- Temporarily duplicate a station/charger ID and confirm startup prints a clear CONFIG ERROR instead of loading an invalid layout.

## Vehicle configuration

- Give the test group `ps-fuel.admin`.
- Third-eye a vehicle and choose **Configure vehicle fuel type**, or use `/fuelvehicleconfig`.
- Configure a custom model as electric with fast charging enabled.
- Confirm all vehicles of that model accept the EV connector after the update without restarting.
- Disable fast charging and confirm the fast option disappears.
- Select automatic detection and confirm the database override is removed.
- Repeat without ACE permission and confirm the menu/action is unavailable or rejected.

## Physical nozzles

- Third-eye a native petrol pump and take its nozzle.
- Confirm the prop attaches to the hand and the rope attaches to the pump.
- Confirm no pickup or refuelling animation plays.
- Insert it into a nearby combustion vehicle and select the correct fuel.
- Confirm plain progress text appears above the vehicle without a background box or stop hint.
- Confirm X can still safely cancel even though it is not displayed.
- Stretch the hose beyond the configured distance and confirm safe cleanup.

## EV charging

- Confirm chargers spawn at configured station coordinates.
- Take the charging connector and attach it to a configured EV.
- Confirm standard charging is available.
- Confirm fast charging appears only for compatible vehicles and chargers.
- Confirm fast charging increases charge faster and costs more than standard charging.
- Confirm combustion vehicles reject the EV connector and EVs reject fuel nozzles.

## FuelOS

- Use `/fuelstation` or G at an ownable station.
- Test station purchase, pricing, withdrawal, ledger, delivery, robbery and fuel-can purchase.
- Use `/fueladmin` with and without `ps-fuel.admin`.
- Use `/repairfuelleak` as an authorised mechanic/admin and confirm an unauthorised player is rejected.

## Persistence and compatibility

- Restart the resource and confirm vehicle model profiles remain.
- Restart the resource and confirm vehicle fuel/station data remains.
- Test `exports['ps-fuel']:GetFuel` and `SetFuel`.
- Confirm a resource depending on `cdn-fuel` resolves to this resource.


## Security and recovery

- Attempt to call `completeRobbery` without a valid start token and confirm no payout occurs.
- Cancel a robbery and confirm the active session is removed.
- Trigger two simultaneous station withdrawals and confirm only one is paid.
- Attempt to save fuel for a different plate/network ID and confirm the server rejects it.
- Complete a delivery without the assigned truck/tanker and confirm it is rejected.
- Disconnect during a delivery and confirm spawned vehicles are removed.
- Stop the resource while holding a nozzle and confirm props, ropes, sounds and targets clean up.
- Confirm all seven `.ogg` files load without NUI 404 errors.
