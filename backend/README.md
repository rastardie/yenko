# YɛnKɔ API

A portable Node.js API for YɛnKɔ. Its source of truth is standard PostgreSQL; it has no Railway-specific application dependency.

## Runtime modes

| Mode | Persistence | Identity |
|---|---|---|
| Unit tests / UI prototype | In-memory demo data | `development-header` actor headers (rejected in production) |
| Local development | PostgreSQL | `local-pin`: username/phone + password or quick PIN, JWT sessions, group-based roles and permissions, admin API |
| Production | PostgreSQL | `oidc`: OIDC/JWKS bearer-token verification (the admin API is not mounted yet) |

Production startup is blocked unless PostgreSQL and OIDC are both configured.

## Local PostgreSQL

`npm run start:local` uses the native PostgreSQL server already installed on macOS and creates/uses the dedicated `yenko_development` database on port `5432`. It never uses or migrates Onboard's database or schema.

```bash
cd backend
npm run start:local
```

The command starts the Homebrew `postgresql@16` service if necessary, applies migrations, ensures seed data exists, and starts the API on port `8080`. To connect the Android emulator, run Flutter with the local API build flag:

```bash
flutter run -d emulator-5554 \\
  --dart-define=YENKO_USE_LOCAL_API=true \\
  --dart-define=YENKO_API_BASE_URL=http://10.0.2.2:8080
```

`start:local` also seeds three development-only accounts (`ladmin` Super Admin, `tst-driver`, `tst-rider`; credentials in `src/seed.js`) and keeps the demo trip bookable. Restart it after any backend change.

For manual checks instead:

```bash
npm run check
TEST_DATABASE_URL='postgresql://<local-user>@127.0.0.1:5432/yenko_test' npm run test:integration
```

Integration tests run one file at a time, refuse to run unless the database name ends in `_test` or `-test`, then truncate only that isolated test database.

## Authentication and administration

Roles and admin permissions come from group membership and are evaluated on every request (`groups`, `group_members`, `permissions`, `group_permissions`). System groups (Super Admins, Admins, Operators, Support Agents, Fleet Managers, Finance, Drivers, Riders) are seeded by migration `006_admin_rbac.sql`; custom groups can be created in the admin console. The admin API lives under `/v1/admin/*` and is documented in `openapi.yaml`; every admin write is recorded in `audit_events`. See `../HANDOVER.md` for the safeguards.

Migrations are checksum-locked after they are applied: add a new numbered file instead of editing an existing one.

## Railway deployment

1. Create separate Railway environments: `development`, `staging`, and `production`.
2. Add a Railway PostgreSQL service. Railway injects `DATABASE_URL` into the API service through a reference variable; do not copy it into source control.
3. Deploy this directory. `railway.toml` uses the Dockerfile, runs migrations as the pre-deploy command, and probes `/health/ready`.
4. For production set `NODE_ENV=production`, `AUTH_MODE=oidc`, `OIDC_ISSUER`, `OIDC_AUDIENCE`, and optional `OIDC_ROLES_CLAIM`. Do not use development actor headers in production.
5. Configure a custom domain, HTTPS, backups/retention, logs/alerts, and a restore drill before storing real user data.

## Portability and recovery

- Schema is standard SQL in `db/migrations/`; migrations are checksummed after application.
- `DATABASE_URL` is the only database connection contract.
- `scripts/backup-postgres.sh` creates a portable `pg_dump` custom-format backup and SHA-256 checksum. Encrypt and copy backups to independent storage; test restores regularly.
- S3-compatible object storage should hold future document/media files—not database blobs.
- Outbox and audit tables are already present; a provider worker can consume them once notifications, payments, or verification are selected.

No live payments, identity-document handling, location tracking, chat, or provider credentials are implemented or stored by this service.
