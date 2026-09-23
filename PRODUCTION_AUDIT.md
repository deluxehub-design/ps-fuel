# PS Fuel 3.2.0 production audit

## Release blockers fixed

- Restored all seven NUI sound files referenced by the manifest/runtime.
- Added server-authorised nozzle, robbery and delivery sessions.
- Added rate limiting and stronger per-session tokens.
- Validated network entity, player distance and plate before fuel persistence.
- Made station withdrawals and robbery deductions atomic with rollback paths.
- Validated assigned delivery truck/tanker and cleaned them on disconnect/stop.
- Added automatic database migrations, indexes, audit logs and retention cleanup.
- Added complete resource-stop cleanup for targets, props, ropes, sounds and blips.
- Added configuration validation and safe defaults for pricing/restocking/rewards.
- Restricted administrative configuration, set-fuel and leak-repair operations.

## Validation performed

- Lua syntax parsing after normalising FiveM backtick model literals.
- JavaScript syntax checks for every shipped runtime bundle.
- Client/server callback and event alignment checks.
- Manifest path and streamed asset validation.
- Station and EV charger ID/reference validation.
- ZIP integrity and SHA-256 generation.

## Still required before commercial release

Run the complete `TESTING.md` checklist on a staging FiveM server with your exact
Qbox, ox_inventory and banking setup. Static validation cannot prove native,
network ownership, rope physics, target placement or payment behaviour under a
real multi-player OneSync session.
