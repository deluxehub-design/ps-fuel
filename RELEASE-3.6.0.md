# PS Fuel 3.6.0

## Startup hotfix

- Fixed a database startup regression where the removed `ensureColumn` migration helper was still called for custom-station columns.
- Framework auto-detection now re-evaluates during startup so Qbox/QBCore/ESX cannot be permanently cached as standalone just because the core was still starting.
- Jerry-can and leak-repair usable-item registration now retries for up to 20 seconds and no longer prints false standalone adapter failures during normal startup ordering.
- The database-ready message is framework-neutral.

PS Fuel 3.6.0 is a gameplay, ownership, physical-nozzle and security release.

## Added

- Fuel recovery / siphoning: use third-eye on a vehicle to securely drain its stored fuel. The server decides the amount and clears wrong-fuel contamination after a successful drain.
- All configured GTA fuel stations are ownable by default unless explicitly marked `forcePublic = true`.
- Buying an unowned station resets its stock to zero. Unowned stations stay supplied; owned stations consume real stock and must be restocked.
- GTA AI supplier deliveries: owners can order fuel and a randomly selected GTA truck driver/tractor/tanker visual arrives, unloads, drives away and despawns. Server inventory rises gradually while unloading.
- Runtime station builder in the admin FuelOS view. Admins can stand at a location and create a persistent ownable station with a spawned GTA fuel pump.
- Runtime EV charger builder in the admin FuelOS view. Admins can place persistent chargers at homes/businesses and link them to a station ID.
- Runtime-created stations and chargers sync to connected clients and survive restarts.
- Physical nozzle workflow: insert the nozzle, press E while beside the vehicle to begin, stop flow, third-eye the vehicle to remove the nozzle, then return it to the original pump.
- EV connectors remain plugged in after charging and permit the player to walk away while the cable remains within charger-to-vehicle range.

## Security

- Delivery rewards are pre-generated and written to a one-time database claim when the job begins; completion can only pay the amount stored by the server.
- Delivery reward claims transition atomically through reserved -> paying -> paid and cannot be replayed.
- Fuel siphon sessions use server-issued one-time tokens, source/entity proximity validation, plate validation and replay consumption before database writes.
- Admin station/charger creation requires ACE admin permission and validates that submitted coordinates are within a few metres of the admin's real server-side ped position.
- NPC delivery stock is server-authoritative. Client visuals never decide delivered amount, station stock or money.
- NPC delivery order amounts are clamped server-side to supplier minimums, available storage and a maximum order ceiling. Newly purchased empty stations can fund the first supplier order from the owner's bank if the business balance is empty.
- Failed bank-funded supplier orders refund into the station ledger instead of creating a client-controlled player-money credit path.
- Existing 3.5.3 outbound-request hardening and deny-by-default money credit limits remain in place.

## Upgrade notes

No manual SQL migration is required when using normal resource startup; PS Fuel creates the new 3.6.0 tables automatically. The SQL installer also includes them for fresh installs.
