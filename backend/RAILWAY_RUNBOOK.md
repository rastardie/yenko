# Railway deployment runbook

## Required environment variables

| Variable | Development | Production |
|---|---|---|
| `DATABASE_URL` | Railway PostgreSQL reference | Railway PostgreSQL reference |
| `NODE_ENV` | `development` | `production` |
| `AUTH_MODE` | `development-header` for test data only | `local-pin` or `oidc` |
| `JWT_SECRET` | any value | a long random value — never the placeholder |
| `OIDC_ISSUER` | not required | required only if `AUTH_MODE=oidc` |
| `OIDC_AUDIENCE` | not required | required only if `AUTH_MODE=oidc`, e.g. `yenko-api` |
| `OIDC_ROLES_CLAIM` | optional | optional, default `roles` |
| `CORS_ORIGINS` | not required (web client is usually run against `localhost` and does not need this) | the deployed PWA's exact HTTPS origin(s), comma-separated, no wildcard — e.g. `https://yenko.pages.dev`. Required for the Cloudflare Pages web client to call this API at all; irrelevant to native Android/iOS. |
| `WEBAUTHN_RP_ID` / `WEBAUTHN_ORIGIN` | `localhost` / `http://localhost:8765` for local web testing | the PWA's bare domain / full origin — in practice the same domain as `CORS_ORIGINS`, just without the scheme for `WEBAUTHN_RP_ID`. Both required together to enable passkeys; dark otherwise. |
| `PORT` | injected by Railway | injected by Railway |

## Release procedure

1. Run `npm run check` and the isolated PostgreSQL integration suite in CI.
2. Deploy development first; Railway executes `node src/migrate.js` before starting the service.
3. Confirm `/health/ready`, database migration state, logs, and a create/list/reserve smoke test using only synthetic users.
4. Promote the same build to staging; repeat the smoke test and perform a backup restore drill.
5. Promote to production only after OIDC configuration, backup retention, monitoring, and data-handling approval are complete.

## Rollback

Application rollback is safe only when the target schema remains compatible. Never alter an applied migration. Add a new forward-only migration for corrective changes. Restore a database backup only through a rehearsed incident procedure; it can discard legitimate writes after the backup point.
