#!/usr/bin/env bash
set -euo pipefail

# Native macOS PostgreSQL is the default local-development path. It keeps YɛnKɔ
# in a dedicated database and does not touch Onboard's database or schema.
# Use npm run start:docker only when an isolated Docker database is preferred.
DEFAULT_DATABASE_URL="postgresql://${USER}@127.0.0.1:5432/yenko_development"
LOCAL_ADMIN_DATABASE_URL="postgresql://${USER}@127.0.0.1:5432/postgres"
using_default_database=false

if [[ -z "${DATABASE_URL:-}" ]]; then
  export DATABASE_URL="$DEFAULT_DATABASE_URL"
  using_default_database=true
fi

wait_for_database() {
  local database_url="$1"
  for _ in {1..15}; do
    if pg_isready --dbname="$database_url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

if [[ "$using_default_database" == true ]]; then
  if ! wait_for_database "$LOCAL_ADMIN_DATABASE_URL"; then
    if command -v brew >/dev/null 2>&1; then
      printf 'Starting native PostgreSQL with Homebrew…\n'
      brew services start postgresql@16 >/dev/null 2>&1 || true
    fi
  fi

  if ! wait_for_database "$LOCAL_ADMIN_DATABASE_URL"; then
    printf 'Native PostgreSQL is unavailable. Start it with `brew services start postgresql@16`, or set DATABASE_URL to a dedicated PostgreSQL database.\n' >&2
    exit 1
  fi

  if ! psql --dbname="$LOCAL_ADMIN_DATABASE_URL" --tuples-only --no-align \
    --command="SELECT 1 FROM pg_database WHERE datname = 'yenko_development'" \
    | grep -qx '1'; then
    printf 'Creating dedicated local database yenko_development…\n'
    createdb --host=127.0.0.1 yenko_development
  fi
else
  printf 'Using explicitly supplied DATABASE_URL. Confirm it is a dedicated YɛnKɔ database.\n'
fi

if ! wait_for_database "$DATABASE_URL"; then
  printf 'PostgreSQL is not reachable at DATABASE_URL.\n' >&2
  exit 1
fi

export NODE_ENV="development"
export AUTH_MODE="${AUTH_MODE:-local-pin}"
export JWT_SECRET="${JWT_SECRET:-yenko-local-development-only-secret-do-not-use-in-production}"
export API_HOST="0.0.0.0"
export PORT="${PORT:-8080}"

node src/migrate.js
node src/seed.js
exec node src/server.js
