# Changelog

## 3.2.2

- Reduced the public fuel-selection UI to a compact payment-dialog-sized layout.
- Added automatic first-run SQL installation from `install/ps-fuel.sql`.
- Kept safe compatibility migrations for existing databases.
- Added a dedicated `version.lua` GitHub release checker.
- Set the default update repository to `deluxehub-evolvenetwork/ps-fuel`.
- Added the `psfuelversion` server-console command.
- Fixed vehicles remaining undriveable or unable to restart after refuelling from empty.
- Improved GTA native, `_FUEL_LEVEL`, `fuel` and `recoilFuel` synchronization.
- Improved compatibility with TGIANN, JG, LS Trucker Simulator and custom vehicle scripts.
- Added `AddFuel`, `RemoveFuel`, lowercase fuel aliases and vehicle-fuel compatibility exports.
- Cleaned UI code and removed the full-screen refuel override.
- Replaced a browser-specific `replaceAll` call with a wider-compatible string replacement.

## 3.2.1

- Previous release.

## 3.2.0

- Production baseline with petrol, EV charging, station ownership, persistence, deliveries, robberies, audit logging and LegacyFuel/cdn-fuel compatibility.
