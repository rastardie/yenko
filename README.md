# YɛnKɔ

**Your Journey, Simplified.** A Flutter app for sharing spare car seats in Accra, with a Node.js + PostgreSQL API.

Read [`HANDOVER.md`](HANDOVER.md) first: it is the source of truth for status, decisions, rules and the next steps. This file is only orientation.

## What works today

- Riders find trips by route, see public pickup junctions and fixed GH₵ prices, and request or cancel a seat.
- Drivers publish trips and see booking requests.
- Sign in with a username and a password **or** a quick PIN; sign up as a rider or driver.
- An **admin console** (dashboard, people, groups and permissions, trips, audit trail) for staff accounts, driven by group-based permissions.
- Notifications inbox, optional device biometrics, and a sign-out that revokes the session on the server.

Not built: maps, payments, identity/vehicle verification, live location, chat, push/SMS. See `HANDOVER.md` for what is deferred and why.

## Run it locally

Two modes:

1. **Mock (default):** in-memory data, no sign-in.
   ```bash
   flutter pub get
   flutter run
   ```
2. **Local API:** Flutter app → Node API → native PostgreSQL. Start the API in its own terminal and restart it after backend changes:
   ```bash
   cd backend && npm run start:local
   ```
   then, in another terminal:
   ```bash
   flutter run -d emulator-5554 \
     --dart-define=YENKO_USE_LOCAL_API=true \
     --dart-define=YENKO_API_BASE_URL=http://10.0.2.2:8080
   ```
   `start:local` applies migrations and seeds three development-only accounts (see `backend/src/seed.js`): a Super Admin `ladmin`, a driver `tst-driver` and a rider `tst-rider`. Never run the seed outside local development.

## Validate

```bash
flutter test
cd backend && npm run check          # unit tests
cd backend && TEST_DATABASE_URL="postgresql://$USER@127.0.0.1:5432/<name>_test" npm run test:integration
```

`flutter analyze` crashes when run from a path containing `ɛ`/`ɔ`; run it from an ASCII copy:

```bash
rm -rf /tmp/yenko_analyze_copy && cp -R . /tmp/yenko_analyze_copy \
  && (cd /tmp/yenko_analyze_copy && flutter analyze); rm -rf /tmp/yenko_analyze_copy
```

## Layout

```text
lib/
├── core/            # config, data clients (auth, trips, admin), models, security, theme
├── features/        # auth, home, trips, bookings, notifications, profile, navigation, admin
└── shared/widgets/  # logo, showcase cards/buttons, watermark backdrop
backend/
├── db/migrations/   # checksum-locked SQL; add a new file, never edit an applied one
├── src/             # domain → application → infrastructure → interfaces (HTTP)
└── test/            # unit tests; test/integration needs a dedicated *_test database
docs/ARCHITECTURE.md # architecture baseline
```

## Branding

The visible name is **YɛnKɔ**. The logo is `assets/app/yenko_logo.png` (the transparent cut-out of `pics/logos/YɛnKɔ Road Trip Logo.png`). It appears on every page through the `YenkoLogo` widget, which writes "Your Journey, Simplified" underneath, scaled to run the full width of the logo. Do not add other wordmark text beside it. Every screen keeps the logo-free city watermark `assets/app/getting_started_city_watermark.png`.

Do not add credentials, provider keys or real user data to this repository.
