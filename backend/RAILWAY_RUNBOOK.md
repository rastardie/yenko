# Railway deployment runbook

## Required environment variables

| Variable | Development | Production |
|---|---|---|
| `DATABASE_URL` | Railway PostgreSQL reference | Railway PostgreSQL reference |
| `NODE_ENV` | `development` | `production` |
| `AUTH_MODE` | `development-header` for test data only | `oidc` |
| `OIDC_ISSUER` | not required | selected identity-provider issuer |
| `OIDC_AUDIENCE` | not required | `yenko-api` or selected API audience |
| `OIDC_ROLES_CLAIM` | optional | role-claim name, default `roles` |
| `PORT` | injected by Railway | injected by Railway |

## Release procedure

1. Run `npm run check` and the isolated PostgreSQL integration suite in CI.
2. Deploy development first; Railway executes `node src/migrate.js` before starting the service.
3. Confirm `/health/ready`, database migration state, logs, and a create/list/reserve smoke test using only synthetic users.
4. Promote the same build to staging; repeat the smoke test and perform a backup restore drill.
5. Promote to production only after OIDC configuration, backup retention, monitoring, and data-handling approval are complete.

## Rollback

Application rollback is safe only when the target schema remains compatible. Never alter an applied migration. Add a new forward-only migration for corrective changes. Restore a database backup only through a rehearsed incident procedure; it can discard legitimate writes after the backup point.
