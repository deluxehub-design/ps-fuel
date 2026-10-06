# PS Fuel 3.5.3 — Security & Exploit Fix Release

PS Fuel 3.5.3 is a bug-fix/security release for 3.5.2. It keeps the 3.5.2 feature set and focuses on hardening server-authoritative paths that can be targeted by event replay, SQL-injection heuristics, or SSRF-style request abuse.

## Fixed

- Delivery completion is now idempotent and rate-limited before the first yielding database operation, preventing repeated callback execution from issuing duplicate rewards.
- Wallet queries no longer interpolate account-column names. Cash and bank paths use fixed SQL statements.
- Legacy schema migrations, station upgrades, and fuel-system repairs no longer build SQL identifiers at runtime.
- Database retention cleanup uses bound interval values instead of string formatting.
- Discord logging accepts only official Discord webhook URLs and rebuilds the request on the fixed `discord.com` origin.
- GitHub update checks use the fixed Deluxe Hub Designs repository and a literal `api.github.com` release endpoint.
- Suspicious-activity reports are rate-limited and bounded before optional Discord logging.

## Upgrade

Replace the 3.5.2 resource with this 3.5.3 build and restart `ps-fuel`. No database migration is required beyond the resource's existing startup schema checks.


## Scanner hardening pass

- Delivery rewards now use a server-issued, database-backed one-time claim. Client requests never provide a payout amount.
- Delivery rewards are capped by `Security.MaxDeliveryReward` (defaults to 50,000 if not configured).
- GitHub update checks use only the literal `https://api.github.com/repos/deluxehub-design/ps-fuel/releases/latest` endpoint.
- Discord logging accepts only official Discord webhook URLs, extracts the webhook path, and sends only to the literal `https://discord.com/api/webhooks/` origin.
