# PS Fuel v3.3.0

## Universal Framework Support

### Added
- Framework bridge with automatic detection.
- Qbox support without a hard manifest dependency.
- QBCore support.
- ESX Legacy support.
- Standalone support.
- vMenu/standalone mode.
- Custom framework adapter export.
- Framework-neutral player, identifier, job, grade, duty, money and usable-item APIs.
- Standalone persistent cash/bank wallet through `ps_fuel_wallets`.
- Configurable standalone starting cash and bank balances.
- Configurable logical duty-job groups for robbery/police-count systems.
- Framework-neutral inventory handling for ox_inventory, QBCore/Qbox inventories and ESX inventory APIs.

### Changed
- Removed `qbx_core` from the hard resource dependency list.
- Fuel station payments, station purchases, delivery rewards and robbery payouts now use the framework bridge.
- Job/grade checks now use the framework bridge.
- Jerry-can usable-item registration now uses the framework bridge.
- Client login/logout resets are no longer hard-coded into the main fuel client.

### Compatibility
- Existing v3.2.2 fuel synchronization, exports and statebag/decorator compatibility remain available.
- Qbox remains fully supported while no longer being mandatory.

# Changelog

## 3.2.2

- Added expanded compatibility for TGIANN, JG Scripts, LS Trucker Simulator, HUDs, garages and custom vehicle resources.
- Added bidirectional synchronization between the internal fuel cache, GTA native fuel, `_FUEL_LEVEL`, statebags and compatibility exports.
- Added external fuel-write detection and first-spawn external fuel restoration.
- Added compatibility exports and fuel-setting events.
- Fixed empty-fuel engine recovery and stale cached fuel overwrites.
- Added configurable external fuel tolerance, statebag name and optional automatic engine restart.

## 3.2.1

- Fixed vehicles remaining undriveable after refuelling from empty.
- Added explicit empty-fuel state cleanup and network-control recovery.
- Added bidirectional native/decorator/statebag fuel synchronization for TGIANN, JG and custom resources.
- Added lowercase, AddFuel/RemoveFuel and vehicle fuel compatibility exports plus set/add fuel events.
- Kept `fuel`, `recoilFuel`, `_FUEL_LEVEL` and GTA native fuel values synchronized.

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
