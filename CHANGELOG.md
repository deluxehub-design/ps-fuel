# Changelog

## 3.2.2

- Fixed vehicles remaining undriveable after refuelling from empty.
- Added explicit empty-fuel state cleanup and network-control recovery.
- Added bidirectional native/decorator/statebag fuel synchronization for TGIANN, JG, LS Trucker Simulator and custom resources.
- Added lowercase, AddFuel/RemoveFuel and vehicle fuel compatibility exports plus set/add fuel events.
- Kept `fuel`, `recoilFuel`, `_FUEL_LEVEL` and GTA native fuel values synchronized.
- Added a server-side GitHub release version checker.
- The checker reads the installed version directly from `fxmanifest.lua`.
- Added automatic update notices when a newer GitHub release is available.
- Added a configurable GitHub repository target and `ps_fuel_github_repo` server convar override.
- Added the `psfuelversion` server-console command for manual version checks.
- Version checks fail safely and never stop or restart the resource when GitHub is unavailable.

## 3.2.1

- Previous release baseline.

## 3.2.0 — Production Release

- Added the missing petrol and EV sound files referenced by the NUI.
- Added server callback rate limiting and stronger random session tokens.
- Made vehicle-fuel persistence validate the networked vehicle and actual plate.
- Replaced the local `/setfuel` command with a server-authorised ACE command.
- Added robbery session tokens, elapsed-time validation, cancellation and atomic payouts.
- Made station withdrawals atomic and restore balances if bank payment fails.
- Added assigned truck/tanker validation to delivery loading and completion.
- Added delivery and robbery cleanup on disconnect/resource stop.
- Added database audit logs, useful indexes and configurable retention cleanup.
- Synchronised configured station labels/capacity into existing database records.
- Added `LegacyFuel` compatibility provider and explicit OneSync dependency.
- Added nozzle cleanup on death/logout and target cleanup on resource stop.
- Added fatal configuration validation for duplicate station/charger IDs and invalid station links.
- Added safe handling for missing/disabled Jerry Can configuration and optional dispatch events.
- Hardened dynamic pricing, automatic restocking and configurable reward ranges against invalid values.
- Restricted fuel-leak repairs to configured jobs or ACE permissions.
- Removed experimental OAL mode to maximise compatibility with third-party natives and resources.
- Updated documentation and public-release testing guidance.
