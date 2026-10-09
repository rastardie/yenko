# Deployment

YɛnKɔ deploys the same way as the sibling `onb` project: there is no GitHub
Actions workflow that deploys anything. Railway and Cloudflare Pages each
connect directly to this GitHub repository and redeploy automatically on
every push to the connected branch (normally `main`). GitHub Actions, if
added later, should stay limited to quality gates (tests/lints) and
optional app-store builds — never the Railway/Cloudflare deploy itself.

## Backend → Railway

The Railway project's service root is `backend/`. Everything Railway needs
already lives there:

- `backend/railway.toml` — tells Railway to build with the Dockerfile, run
  `node src/migrate.js` as the **pre-deploy command** (so a new release
  never serves traffic on a schema it hasn't migrated yet), start with
  `node src/server.js`, and health-check `/health/ready`.
- `backend/Dockerfile` — multi-stage-free single `node:22.14.0-alpine3.21`
  image, installs with `npm ci --omit=dev`, runs as a non-root `yenko`
  user, exposes `8080`.
- `backend/RAILWAY_RUNBOOK.md` — the full environment variable reference
  and release/rollback procedure. Read it before touching production.

### First-time setup

1. In Railway, create a project, add a PostgreSQL database, and add a
   service pointing at this GitHub repo with **root directory `backend`**.
2. Set the environment variables from `backend/RAILWAY_RUNBOOK.md`'s table.
   At minimum for a working deployment: `DATABASE_URL` (Railway's own
   Postgres reference), `NODE_ENV=production`, `AUTH_MODE=local-pin`,
   `JWT_SECRET` (a long random value, not the placeholder).
3. Once you know the Cloudflare Pages domain (see below), set
   `CORS_ORIGINS` to that exact `https://...` origin, and `WEBAUTHN_RP_ID`
   / `WEBAUTHN_ORIGIN` to the same domain if you want passkeys to work on
   the deployed PWA.
4. Push to the connected branch. Railway builds the Dockerfile, runs the
   migration pre-deploy command, then starts the service.
5. Confirm `GET https://<your-railway-domain>/health/ready` returns
   `{"status":"ready"}`.

### Every subsequent deploy

Just push to the connected branch (normally `main`). Railway rebuilds and
redeploys automatically — nothing else to run.

## Frontend (PWA) → Cloudflare Pages

Cloudflare Pages is configured entirely in the Cloudflare dashboard
(connected to this GitHub repo), plus one build script in this repo:
`tool/build-cloudflare-pages.sh`. There is no `wrangler.toml`, no
`_headers`/`_redirects`, no Pages Functions — none of that is needed here.

### First-time setup

1. In Cloudflare Pages, create a project connected to this GitHub repo.
2. **Build command:** `bash tool/build-cloudflare-pages.sh`
3. **Build output directory:** `build/web`
4. **Environment variable (required):** `YENKO_API_BASE_URL` — the
   Railway backend's `https://` origin (no trailing slash), e.g.
   `https://yenko-production.up.railway.app`. The build script fails
   loudly if this is unset.
5. Note the resulting `*.pages.dev` domain (or your custom domain once
   attached), then go back to Railway and set `CORS_ORIGINS` to that exact
   origin — the web client cannot call the API cross-origin until you do
   this; see "Order of operations" below.
6. Trigger a deploy (push to the connected branch, or use "Retry
   deployment" in the dashboard) so the build picks up the `CORS_ORIGINS`
   change on the Railway side — Cloudflare's own `YENKO_API_BASE_URL`
   setting does not need to change again.

### Every subsequent deploy

Just push to the connected branch. Cloudflare Pages rebuilds and
redeploys automatically.

### Order of operations the first time (origins reference each other)

Railway's `CORS_ORIGINS` needs Cloudflare's domain, but Cloudflare's build
needs Railway's domain — so bring Railway up first, note its domain, set
that as `YENKO_API_BASE_URL` in Cloudflare, deploy Cloudflare once to learn
its own domain, then go back and set `CORS_ORIGINS` on Railway to that.
Until that last step, the deployed PWA will load but every API call will
fail in the browser console with a CORS error (requests to native
Android/iOS are never affected by this, since CORS is a browser-only
restriction).

## What is NOT automated

- No GitHub Actions workflow builds or deploys anything today, matching
  `onb`'s pattern. If you later want an Android release pipeline (AAB to
  Google Play, as `onb` has), that would be a new, separate workflow —
  Railway and Cloudflare deployment should stay exactly as described
  above regardless.
- No database seeding runs on deploy. `backend/src/seed.js` is a
  local-development-only script; never run it against a production
  database.
- No automated rollback. See `backend/RAILWAY_RUNBOOK.md`'s rollback
  section — schema changes are forward-only.
