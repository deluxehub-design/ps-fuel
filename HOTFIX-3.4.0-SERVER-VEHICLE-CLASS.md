# PS Fuel 3.4.0 server vehicle-class hotfix

This hotfix fixes repeated FXServer errors caused by calling `GetVehicleClass` from `server/advanced.lua`.

FiveM exposes the vehicle class reliably on the client. Advanced client callbacks now report the class, mirror it to `Entity(vehicle).state.psFuelClass`, and the server validates the value before using it.

Affected systems fixed:

- Advanced vehicle state and trip data
- Tank capacity/class lookup
- Siphoning
- Vehicle-to-vehicle fuel transfer
- Portable fuel containers
- Mobile refuelling
- Private/home/business fuel points
- Private-point fuel purchase history

The public `GetFuel` / `SetFuel` compatibility interface remains unchanged.
