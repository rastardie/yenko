# YɛnKɔ — Continuation Handover

**Last updated:** 2026-10-05

## Active workspace

```text
/Users/andrewstardie/Documents/TUTS/TESTS/ynk/YɛnKɔ
```

Note the path moved since the last handover: it is now under `TESTS/ynk/YɛnKɔ`, not `TESTS/YɛnKɔ` directly. The project is **still not a Git repository** (`git status` returns "not a git repository"). Nothing here is reversible via git; be careful with destructive edits.

YɛnKɔ is an Accra spare-seat-sharing Flutter application with a Node.js/PostgreSQL backend. It now has three working client targets:

1. **Mock mode** — in-memory data, no sign-in, for pure UI iteration.
2. **Android (native local full-stack)** — Flutter → local Node API → local PostgreSQL. Confirmed working.
3. **Web/PWA** — same backend, now fixed this session (see below). Confirmed booting without errors; a full click-through login in-browser was not completed.

## Non-negotiable branding rules

- Product name is **YɛnKɔ**, with `ɛ` and `ɔ`. Never reintroduce **FaMe**.
- The logo in actual use is `assets/app/yenko_logo.png` (1600×386 wide lockup: car/road emblem + "YɛnKɔ" wordmark). This is what `YenkoLogo` in `lib/shared/widgets/yenko_widgets.dart` renders and what Android/iOS native icons were generated from in an earlier session.
- **Correction from the last handover:** that document claimed the asset was `assets/app/yenko_journey_logo_emblem.png` and that `yenko_logo.png` was "superseded." That was wrong — `yenko_logo.png` is the live, registered, in-use asset (confirmed via `pubspec.yaml` and a grep of `lib/`). There is no `yenko_journey_logo_emblem.png` file in the repo.
- `assets/yenko-logo-lockup-preview.png` and `assets/yenko-logo-lockup.svg` exist on disk but are **not registered in `pubspec.yaml` and not referenced anywhere in `lib/`**. Critically, `yenko-logo-lockup-preview.png` is the **old FaMe-branded logo** ("FaMe — Fa me lift. Same road. Shared ride."). It is dead/unused, but should be **deleted**, not left lying around, since it violates the branding rule if anyone mistakes it for current.
- The full-screen, logo-free city watermark (`assets/app/getting_started_city_watermark.png`) is unchanged and still used via `YenkoShowcaseBackdrop`.
- PWA icons (`web/icons/*.png`, `web/favicon.png`) were generated this session by cropping the car/road emblem out of `yenko_logo.png` (crop region `(0,0)–(540,386)` on the source file — found by trial since there's no separate square-mark asset). Manifest/HTML title were rebranded from the Flutter template defaults ("yenko_app") to "YɛnKɔ".

## What changed since 2026-10-03 (the last handover)

The last handover undersold how much exists now. A full admin console, RBAC system, email+social auth, and PWA support were all added or substantially built out. Two subagent investigations this session (one backend, one Flutter UI) confirmed the following in detail — see their findings below rather than relying on code comments alone.

### 1. Backend: RBAC and admin system (migrations 006–009)

Two-layer model: coarse `groups.role` (passenger/driver/admin/super_admin/operator/support/fleet_manager/finance, or NULL for custom groups) plus fine-grained `resource:action` permissions joined via `group_permissions`. A user's effective permissions are the union across all their groups, recomputed every request in `postgres-admin-repository.js`.

26 permissions total across three migrations:
- **006**: `users:read/create/update/manage_status/reset_credentials`, `groups:read/create/update/delete/assign_members/assign_permissions`, `trips:read/cancel`, `reservations:read`, `dashboard:read`, `audit:read`
- **008**: `users:approve`, `users:delete`, `reservations:manage`, `reports:read`
- **009**: `admin:access` (gates the entire Admin area), `trips:offer`, `trips:manage_own`, `reservations:book`, `reservations:cancel_own`, `reservations:view_own` (the last five turn rider/driver app actions into real, auditable, revocable permissions instead of being hardcoded to role)

Default grants: Super Admins hold every permission (fixed, cannot be edited — `setGroupPermissions` rejects attempts). Admins hold everything except `audit:read`. Operators/Support/Fleet Managers/Finance hold narrower read-mostly scopes (see migration 006 for exact lists). **Only Super Admins and Admins hold `admin:access` by default** — other staff groups have real permissions but no Admin menu until an administrator explicitly grants it on their group.

Escalation guardrails in `admin-service.js`: only a super_admin can manage super_admin accounts or Super Admins group membership; an admin can only grant/revoke permissions they themselves hold; the last active super admin cannot be deleted/suspended/demoted; nobody can suspend/delete their own account; system groups cannot be renamed/deleted.

Every admin write requires a fresh **admin-action token** — a 5-minute HS256 JWT obtained by re-entering the password/PIN at `POST /v1/auth/admin-action-token`, sent as `x-admin-action` on the write request. Brute-force protection on this exists but is **in-memory only** (`adminActionFailures` Map in `auth-service.js`) — lost on restart, not shared across instances, so it will not work correctly behind more than one replica. Every mutation writes an `audit_events` row in the same transaction as the change.

Full admin API surface (`/v1/admin/*`, all gated by `admin:access`, then per-action permission): summary, metrics (period/custom range with per-driver stats and daily series), dashboard, users (CRUD + approve/deny + reset-password + soft delete), groups (CRUD + permission/member assignment), trips (list/get/cancel — cancelling atomically cancels all open bookings and notifies everyone), bookings (list/confirm/cancel), reports/bookings (same shape, separate permission, larger page size), audit-logs (list + distinct actions).

**Flutter side mirrors this exactly** via `session.can('resource:action')` checks (`AdminApiClient`, `LocalAuthSession`). The admin console is one bottom-nav tab (6th, after Home/Offer/Rides/Messages/Profile), only rendered when the signed-in session has `admin:access` (checked once in `main.dart` when building the `AdminApiClient` — the root screen itself does not re-check per permission, so passing an `adminClient` always means "this account gets the tab"). Sections: People (Users, Groups) and Operations (Trips, Bookings), plus full pages for Dashboard, Reports, and Audit. CSV "export" in Reports is clipboard-copy only, not a file/share — this is by design per code comments, not a bug.

### 2. Backend: email + social authentication (migration 010)

**Email signup** (`POST /v1/auth/email/signup`) is real: email + password (bcrypt) + mandatory self-attested legal name (surname + given names, separate from the friendly display name) + optional username/role/home area. A 6-digit OTP (5-minute TTL, 5 attempts) is issued for email verification.

**Mail delivery is a stub.** The only sender is `ConsoleMailSender` (`backend/src/infrastructure/mail/console-mail-sender.js`), which just logs the message. It is wired only when `MAIL_ENABLED=true`. Whenever no real mail sender is configured, the OTP is **returned directly in the API response** as `devCode` — the code's own comment says "Never do this in production." The Flutter verification screen (`email_verification_screen.dart`) already displays this `devCode` on-screen in dev, and also offers **"Skip for now"** — so email verification is currently entirely optional/bypassable end-to-end. The same `devCode` leak pattern applies to phone verification and PIN-reset OTPs (no SMS sender exists at all; `smsSender` is always null in `app.js`).

**Social sign-in** (`POST /v1/auth/social`) is further along than the previous handover assumed:
- **Google and Apple**: real, working `OidcSocialProvider` — verifies the ID token's signature against the provider's live JWKS endpoint and checks issuer/audience. Only needs `GOOGLE_CLIENT_ID`/`APPLE_CLIENT_ID` env vars to activate (no code changes needed server-side).
- **Facebook**: real `FacebookSocialProvider` — verifies via Graph API's `/debug_token` then fetches `/me`. Needs `FACEBOOK_APP_ID` + `FACEBOOK_APP_SECRET`. Untested against the live Graph API in this project.
- **X/Twitter**: real `TwitterSocialProvider` call to `/2/users/me`, but X's public API returns no email, so every X sign-in is forced through the mandatory-username-and-legal-name first-time path — it can never auto-link by email. Only gated by `TWITTER_ENABLED=true`, with no secret verification (it just forwards whatever bearer token the client sends).

**The gap is entirely client-side**: `social_auth_buttons.dart` has no native SDK integration for any provider yet. It always sends an empty token purely to probe server status, which is why tapping any button shows "not enabled" / "configure this provider" regardless of server config. This was already logged as a pending external-accounts item (see below) — that section is still accurate and unchanged.

### 3. Flutter: PWA/web support added and a boot-crash fixed

Flutter web was scaffolded this session (`flutter create . --platforms web`), branded (manifest/title/icons from the real logo, not the dead FaMe asset), and then found to **crash immediately on boot** with `Unsupported operation: Platform._version`.

**Root cause** (confirmed via a readable `flutter run -d chrome` debug stack trace, not guesswork): `local_auth_client.dart`, `local_api_trip_repository.dart`, and `admin_api_client.dart` all built their HTTP clients with `dart:io`'s `HttpClient`. That constructor internally reads `Platform.version` to pick HTTP behavior, which is unimplemented in a browser and throws synchronously — this happened in `main.dart`'s `initState`, before any screen rendered, which is why it looked like a total boot failure rather than a login-specific bug.

Two earlier fix attempts in this session wrongly blamed `local_auth` (its web absence) and did not resolve it — noted here so the mistake isn't repeated. The real fix: migrated all three network-client files from `dart:io HttpClient` to `package:http` (`http: ^1.6.0`, now a pinned dependency), which has a genuine, correct web implementation and works unchanged on Android/iOS. Also added a conditional-import split (`biometric_backend_io.dart` / `biometric_backend_web.dart`) so `local_auth` (which has no official web backend) is never imported at all when compiling for web — this was good practice to keep even though it wasn't the actual bug.

Two existing test files (`local_auth_client_test.dart`, `local_api_trip_repository_test.dart`) mocked the old `HttpClient` type and were updated to use `http.Client`.

**Verified this session:**
- `flutter test` — all 39 tests pass (6 in `admin_test.dart` groups/standalone + others across all 6 test files)
- `flutter analyze` (from the required ASCII-only `/tmp` copy — see below) — no issues
- `flutter build web` — succeeds
- Headless Chrome load of the built `build/web` output — **0 console/page errors** (previously crashed every time)

**Not verified:** an actual login submission click-through in the browser. The crash-fix was confirmed at the "app boots cleanly" level, not "a user can sign in via the web UI" level. **This is the first thing to confirm next session.**

### 4. Flutter: new screens not in the previous handover

- `email_signup_screen.dart`, `email_verification_screen.dart` — UI for the email+password flow described above.
- `social_auth_buttons.dart` — the stub probe described above.
- `features/admin/*` (12 files) — the entire admin console described above.
- `features/startup/yenko_splash_screen.dart` — a branded splash shown for ~1.6s on launch before the landing/app screen, to guarantee the wide banner logo is seen even though the OS system splash can only show a square icon.
- `lib/core/data/admin_api_client.dart` — the admin HTTP client (~30KB, by far the largest data file).
- `lib/core/security/biometric_backend_io.dart` / `biometric_backend_web.dart` — new this session, see above.

## Local development setup

### Backend

```bash
cd "/Users/andrewstardie/Documents/TUTS/TESTS/ynk/YɛnKɔ/backend"
npm run start:local
```

This runs migrations and the seed script, then starts on `0.0.0.0:8080` with `AUTH_MODE=local-pin`. **The running process does not reliably pick up code changes** — restart after backend edits (this was re-confirmed working correctly this session: the server picked up new password-auth code without an explicit restart in one case, but do not rely on that).

npm scripts (`backend/package.json`): `start`, `start:local`, `start:docker` (spins up a docker-compose Postgres on port 5433 with an embedded local-only password — fine for local, never for prod), `db:migrate`, `db:seed`, `db:backup`, `test` (`node --test test/*.test.js`), `test:integration` (Postgres-backed, `--test-concurrency=1`), `check` (syntax-checks every `src/*.js` file, then runs `test`).

Seeded accounts are defined in `backend/src/seed.js` (passwords/PINs intentionally not repeated in this document — read the file):

| Username | Role |
| --- | --- |
| `ladmin` | admin (also a passenger) |
| `tst-driver` | driver (also a passenger) |
| `tst-rider` | passenger |

`seed.js` updates credentials on existing rows in place, so re-running it is always safe.

### Android

```bash
cd "/Users/andrewstardie/Documents/TUTS/TESTS/ynk/YɛnKɔ"
flutter run -d emulator-5554 \
  --dart-define=YENKO_USE_LOCAL_API=true \
  --dart-define=YENKO_API_BASE_URL=http://10.0.2.2:8080
```

Confirmed working, including the sign-in flow, as of this session (user confirmed "android is fine").

### Web/PWA

```bash
cd "/Users/andrewstardie/Documents/TUTS/TESTS/ynk/YɛnKɔ"
flutter build web --dart-define=YENKO_USE_LOCAL_API=true --dart-define=YENKO_API_BASE_URL=http://localhost:8080
cd build/web && python3 -m http.server 8765
# open http://127.0.0.1:8765/
```

Note the API base URL is `localhost`, not `10.0.2.2` (that address is Android-emulator-specific and does not exist on web — this is just a `--dart-define`, no code change needed; `AppConfig` in `lib/core/config/app_config.dart` just reads the define).

For live-reload development instead of a static build: `flutter run -d chrome --web-port=<port> --dart-define=...` (requires `CHROME_EXECUTABLE` env var if Chrome isn't on the default path check).

### Static analysis caveat (unchanged from before)

`flutter analyze` fails directly from this Unicode path due to a known analysis-server/LSP bug. Always run it from an ASCII copy:

```bash
rm -rf /tmp/yenko_analyze_copy && cp -R "/Users/andrewstardie/Documents/TUTS/TESTS/ynk/YɛnKɔ" /tmp/yenko_analyze_copy \
  && (cd /tmp/yenko_analyze_copy && flutter analyze); rm -rf /tmp/yenko_analyze_copy
```

`flutter test` and builds run fine directly from the real path.

## Pending — external accounts (blocked on the user, not on code)

Unchanged in substance from the last handover, but now confirmed more precisely: the backend verification code is real and working for Google/Apple (OIDC) and Facebook (Graph API), and functional-but-unverified for X. All four are dark until env credentials exist, and **none has a native Flutter SDK integration yet** — `social_auth_buttons.dart` only probes server status.

| Provider | Account action required (user) | Resulting values needed | Backend env var(s) | Flutter native package still to add |
| --- | --- | --- | --- | --- |
| Google | OAuth consent screen + OAuth client IDs (Android/iOS/Web) in Google Cloud Console; register SHA-1 (debug now, release later) | Client ID(s) | `GOOGLE_CLIENT_ID` | `google_sign_in` |
| Apple | Apple Developer Program ($99/yr); enable Sign in with Apple capability; Services ID if needed | Services ID / bundle ID | `APPLE_CLIENT_ID` | `sign_in_with_apple` |
| Facebook | Facebook Developers app; Android package + key hash, iOS bundle ID + URL scheme; review for scopes beyond public profile/email | App ID + Secret | `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET` | `flutter_facebook_auth` (tbd) |
| X (Twitter) | X Developer portal project/app; OAuth 2.0 user auth with correct scopes | Client ID | `TWITTER_ENABLED=true` | native OAuth2/PKCE flow (tbd) |

Apple's App Store rule: if any other social login ships on iOS, Sign in with Apple must also be offered — not optional once Google/Facebook ship there.

## Known issues and small debts

- `assets/yenko-logo-lockup-preview.png` is dead FaMe-branded art sitting in the repo — delete it (flagged above, not yet acted on this session since it's unreferenced and therefore low-risk, but it should go).
- Email verification is fully skippable (`Skip for now` button) and OTP delivery is dev-stubbed (`devCode`). Fine for development, must be closed off before any real users sign up with email.
- No SMS sender exists at all; phone verification and PIN-reset flows share the same `devCode` leak pattern as email.
- Admin-action brute-force lockout is in-memory only — will not function correctly once there is more than one backend instance.
- No general HTTP rate limiting anywhere in the backend (confirmed via code read, not just absence of config) — login, signup, OTP request, and social endpoints are all unthrottled except the narrow admin-action and OTP-attempt counters.
- No CORS handling and minimal security headers (`x-content-type-options: nosniff`, `cache-control: no-store`, `x-request-id`) — expected to sit behind a reverse proxy, but that proxy does not exist yet either.
- bcrypt cost factor is 10 — acceptable, on the low side for a 2026 production deployment.
- Facebook/Twitter social provider HTTP calls have no timeout/abort — a hanging provider call blocks the request.
- `lib/core/data/local_api_trip_repository.dart` and `admin_api_client.dart` both carry `// ignore_for_file: prefer_initializing_formals` (constructor param names intentionally differ from private fields) — cosmetic, not a bug.
- `_pinController`/`_confirmPinController` variable names in the auth screens still don't match that they hold passwords — cosmetic rename still pending from the last handover.

## Recommended immediate next session

1. **Confirm an actual sign-in through the PWA's UI** in a real or headless browser — the crash fix was verified at the "boots without error" level, not "a user can complete sign-in" level.
2. Delete the dead `assets/yenko-logo-lockup-preview.png` (FaMe branding) and `assets/yenko-logo-lockup.svg` if confirmed unused, or wire the SVG in properly if it's meant to replace the PNG lockup.
3. Decide and implement a real transactional email sender (SMTP/SES) to close the `devCode` leak before any real email signups happen; same decision needed for SMS before enabling phone verification/PIN-reset in production.
4. Add real HTTP rate limiting (at minimum: login, signup, OTP request, admin-action-token) before any public exposure.
5. Replace the in-memory admin-action lockout with a shared store (Postgres row or Redis) if/when the backend runs more than one instance.
6. If moving toward real social sign-in, start with Google (lowest friction: no paid account, no app review) — create the Google Cloud OAuth client IDs, then add `google_sign_in` to the Flutter app and wire a real token into `social_auth_buttons.dart`.
7. Initialize Git. This is now overdue — RBAC, admin console, PWA support, and a boot-crash fix have all happened with zero version history. Treat this as high priority, not optional polish.

## Holistic suggestions — future add-ons

Looking at the system as a whole (ride-sharing marketplace + admin back-office + multi-platform client), here is where the biggest gaps and highest-leverage additions are, organized by theme rather than by file:

### Trust and safety (currently the weakest layer for a ride-sharing product)
- **Driver verification**: no vehicle registration, license, or document upload exists anywhere — `postTrip` still hard-codes "Vehicle details pending verification" (per the previous handover; not re-verified this session but no vehicle table exists in any migration through 010). This is a prerequisite for a real pilot, not a nice-to-have.
- **In-app ratings** for drivers and riders after trip completion — the data model (trips, bookings) could support this with one more table, and it directly affects trust in a peer-to-peer carpool model.
- **SOS/emergency and trip-sharing with a trusted contact** — nothing exists for this yet; for a transportation app this is usually expected before public launch, especially given the women-only trip filter already signals safety-consciousness in the product.
- **Report/block a user** — no moderation primitive exists between riders and drivers.

### Payments (currently entirely absent)
- The admin dashboard and reports already compute "fare value" from booked seats, but there is no payment collection, driver payout, or reconciliation anywhere. Ghana's dominant rails are MTN MoMo, Telecel Cash, and AirtelTigo Money — integrating via an aggregator (Paystack, Flutterwave, or Hubtel) would unlock the core transaction loop the whole admin Reports/Metrics screens are clearly already designed to visualize once real money exists.
- A wallet/ledger (double-entry) for driver settlement would follow naturally once payment collection exists.

### Communication and delivery (the "write path" is further ahead than the "deliver path")
- Email **sending** is stubbed (console-only); the same is true for SMS. Both need real providers before any of the OTP/verification flows are production-safe. This is the most concrete, scoped, low-risk next engineering task — pick one provider per channel and swap the sender implementation (the `MailSender` interface already exists, so this is an adapter, not a redesign).
- Push notifications (FCM/APNs) for trip updates, booking confirmations, and admin alerts — there's already a notification concept in the data model (`notifications_screen.dart`, `/v1/me/notifications`), so push would extend an existing pattern rather than invent one.
- In-app chat between matched driver and rider — currently a placeholder tab (`features/messages`-equivalent via the Messages bottom-nav item); building this out would close the loop between "booked a seat" and "actually coordinating the pickup."

### Operational maturity (the admin console is strong; the operations behind it are thin)
- The admin console (dashboard, reports, audit) is genuinely well-built, but it has no background worker layer behind it. Add: an outbox/event publisher so notifications and side effects don't rely on being inline with the request; scheduled pruning of expired sessions/OTPs; audit retention policy.
- Structured logging and basic observability (error tracking, uptime checks) — right now the only signal is `console.error` on unexpected failures.
- CI: run `flutter test`, `flutter analyze`, `npm run check`, and the integration suite on every change. This has zero cost to add relative to the size of the codebase that currently has no safety net at all (no git, no CI).

### Platform coverage
- iOS was scaffolded long ago but has not been built/run/verified in any recent session — worth a build-and-smoke-test pass now that Android and web are both confirmed working, since the three platforms share the same Dart code and the risk is low.
- The PWA, now that it boots, should get a manifest/service-worker review for actual offline/installability behavior (Flutter's default web template includes a service worker, but whether it's configured well for a flaky-network ride-sharing use case in Accra hasn't been assessed).

### Compliance (Ghana-specific, not yet addressed anywhere)
- Data Protection Act 2012 (Act 843) registration and a real privacy policy/terms before any real user data is collected — currently legal name, email, and phone are all collected with no stated retention or consent flow.
- Given the women-only trip filter is already a product feature, this is a good candidate for an early trust-and-safety and legal pass together, since both touch the same sensitive-data questions.

## 2026-10-08 session — personalization + role-based home screens

### Workspace path correction

The "Active workspace" note at the top of this file (`.../ynk/YɛnKɔ`) is **stale/wrong**. Re-verified this session: `.../ynk/YɛnKɔ` is a near-empty leftover directory containing only a `build/` subfolder — not a real Flutter project (no `lib/`, `pubspec.yaml`, etc. inside it). The actual, live project root is:

```text
/Users/andrewstardie/Documents/TUTS/TESTS/ynk
```

`lib/`, `backend/`, `pubspec.yaml`, `android/`, `ios/`, `web/` all live directly here. Treat any future handover text that says otherwise as wrong until re-confirmed. Still no git repository at this path (`git status` → "not a git repository") — initializing git remains overdue per the previous handover's recommendation #7.

### Problem identified

1. `PassengerHomeScreen` hardcodes `"Hello, traveller 👋"` — never uses `LocalAuthSession.displayName`, even though that field is already populated correctly and already flows into `ProfileScreen`. Pure wiring gap, no backend change needed.
2. **There is no driver-specific screen anywhere in the codebase** (confirmed: no `driver*` file under `lib/features/`). `YenkoRootScreen._tabs()` shows every signed-in account — passenger or driver — the identical tab set: Home (a rider search/discovery screen), Offer (post a ride — a driver action oddly available to everyone), Rides, Messages, Profile. The only role-based branch that exists today is the Admin tab (gated on `session.hasAdminAccess`).
3. `LocalAuthSession.role` (`'passenger'` / `'driver'` / staff roles) and `.displayName` already exist and are reliable — this is purely a Flutter-side routing and UI gap, not a data-availability gap.

### Data model constraint discovered (important for scoping the driver screen)

`TripRepository` (`lib/core/data/trip_repository.dart`) has **no accept/decline step for bookings** — `requestSeat()` directly decrements `seatsAvailable` and inserts a `Booking` with status `requested`; there is no driver-side approval action anywhere in the interface or either implementation (`InMemoryTripRepository`, `LocalApiTripRepository`). So a driver dashboard can show "your posted trips and who/how many seats are booked against them" (via the already-existing `driverTripSummaries` getter — `List<DriverTripSummary>`, each with `trip`, `seatsBooked`, `bookingCount`), but **cannot** show a request-queue with accept/decline buttons without a model + backend change first. Scoped this round's driver screen to what the data already supports; flagged the accept/decline queue as a separate, larger follow-up (needs a new booking status + driver-facing endpoint, not just UI).

### Decisions made (documented here since no one was blocking on them before proceeding)

1. **Passengers no longer see "Offer a ride" as a quick action/tab.** Real Uber/Bolt treat becoming a driver as a separate, deliberate onboarding path, not a casual button next to ride search. `PostTripScreen` (now effectively "driver-only") stays reachable only from the driver tab set.
2. **Driver screen is UI + existing-repository-wiring only this round** — no backend changes. It surfaces `driverTripSummaries` and `activeBooking`-equivalent state that the repository already computes; it does not add request accept/decline (blocked on the model gap above).

### Plan (in progress)

1. **First-name greeting** — thread `session?.displayName` down into `PassengerHomeScreen` (and the new driver screen), parse the first token as the first name, fall back to "traveller" when `session == null` (mock mode). *(Status: next up.)*
2. **Role-based tab routing** — branch `YenkoRootScreen._tabs()` on `session.role`:
   - `driver` → new `DriverHomeScreen` (dashboard) + `PostTripScreen` (offer) + `TripTrackingScreen` (reused as-is — it is already trip/booking-agnostic, not passenger-specific) + `NotificationsScreen` + `ProfileScreen`.
   - `passenger` → existing `PassengerHomeScreen` (search/discover) + `TripTrackingScreen` + `NotificationsScreen` + `ProfileScreen`. No Offer tab.
   - Mock mode (`session == null`) → keep today's full tab set (can't branch on a role that doesn't exist yet); this only affects signed-in local-API sessions.
   - Admin tab logic untouched.
3. **New `DriverHomeScreen`** (`lib/features/home/driver_home_screen.dart`): greeting with first name; online/offline toggle (presentational only — no backend "availability" field exists, flagged as cosmetic/local state, not persisted); list of the driver's own posted trips via `driverTripSummaries` (route, seats booked/available, expected fare); entry point into "Offer a ride"; rating/trip-count summary reusing fields already on `Trip`.
4. **Passenger screen cleanup** — remove the "Offer a ride" `_QuickAction` tile from `PassengerHomeScreen` to match decision 1 above.
5. **Verify** — `flutter test`; `flutter analyze` via the mandatory ASCII `/tmp` copy workaround (ocumented earlier in this file — the Unicode path breaks analysis directly); manual read-through confirming mock mode (`session == null`) still renders without a null-role crash.

### Explicit non-goals this round (don't re-litigate without new input)

- No booking accept/decline workflow (needs backend + model work, see constraint above).
- No real driver "online/offline" persistence, no GPS/live location, no payments — none of that exists yet anywhere in the stack and is out of scope for a UI personalization/routing pass.
- No change to the Admin tab or RBAC system.

### Status: implemented and verified this session

All five plan steps above were completed:

1. `PassengerHomeScreen` now takes an optional `displayName` and greets with `'Hello, ${firstNameOf(displayName)} 👋'`; falls back to "traveller" when `displayName` is null/blank (mock mode, or a blank name). `firstNameOf` is a public top-level helper in `passenger_home_screen.dart`, reused by the new driver screen.
2. `YenkoRootScreen._tabs()` now branches on `session?.role`:
   - `session == null` (mock mode) → unchanged, full original tab set (Home/Offer/Rides/Messages/Profile), since there's no role to branch on.
   - `role == 'driver'` → Home tab renders the new `DriverHomeScreen`; Offer tab (existing `PostTripScreen`) is kept.
   - any other signed-in role (`passenger`, staff roles, etc.) → Home tab renders `PassengerHomeScreen`; **no Offer tab**.
   - Admin tab logic (`hasAdminAccess`) is untouched and still appended last regardless of the above.
3. New file `lib/features/home/driver_home_screen.dart` — `DriverHomeScreen`: first-name greeting, a presentational online/offline `Switch` (local state only, not persisted — no backend field exists), three stat tiles (active trips, expected fare, completed trips) computed from the already-existing `TripRepository.driverTripSummaries`, an "Offer a new ride" button wired to switch to the Offer tab, and a list of the driver's own open/confirmed/in-progress trips with seats-booked/open and expected fare per trip. No accept/decline UI, consistent with the non-goal above.
4. `PassengerHomeScreen`'s "Offer a ride" quick-action tile was removed and replaced with a "Saved places" tile (placeholder, matches the existing non-functional pattern of the other quick actions like Wallet/More) to keep the 4-tile row intact without implying a feature that doesn't exist.
5. Verified: `flutter analyze` (via the mandatory `/tmp` ASCII-copy workaround) — no issues. `flutter test` — all 40 tests pass. Three pre-existing tests in `test/admin_test.dart` encoded the old "every signed-in role sees Offer" assumption and were updated to match the new role-based behavior (`admins keep the regular tabs…`, `riders keep the familiar tabs and get no admin tab`, and the sign-out-tooltip-on-every-tab test); a new test (`drivers get a dashboard home tab and keep the Offer tab`) was added to cover the driver path, including the first-name greeting.

### Still not done — carried forward, not newly discovered

- Still no git repository anywhere in this project. This has now been flagged in two consecutive handovers as high priority; strongly recommend initializing git before any further feature work, given the amount of uncommitted change accumulating (RBAC, admin console, PWA fix, and now this role-routing change, all with zero version history).
- Booking accept/decline (a real request queue for drivers) is the natural next step once git exists, since it is model + backend + UI, i.e. a bigger unit of work than anything done this session.
- The passenger "Wallet", "Saved places", "More" quick actions, and the "My rides" tile, remain non-functional placeholders (pre-existing, not introduced this session) — `onPressed` is unset or a no-op on `_QuickAction`.

### Git initialized (2026-10-08, later same session)

Done — `git init`, default branch renamed `master` → `main`, initial commit `6c8a53f` with 236 files. Author came from the already-configured global git identity (`Tardie <rastardie@gmail.com>`), not set explicitly this session.

Before committing, `.gitignore` was extended (it previously only covered Flutter/IDE artifacts) to also exclude:
- `node_modules/`, `backend/node_modules/`, `backend/.env`, `.env` — none of these were present as real secrets at commit time (`backend/.env.example` is a placeholder template with `change-me` values, confirmed by reading it; no actual `.env` file exists anywhere in the tree), but they must never be tracked once one is created locally.
- `/YɛnKɔ/` and `/yale/` — two small leftover/stray directories at the project root that are not part of the real app (see "Workspace path correction" above; `yale/` is 12K of unknown leftover content, `YɛnKɔ/` is an empty build-artifact-only folder). Left on disk, just untracked, in case anything in them turns out to matter — nothing was deleted.

What's now safely under version control: the full Flutter `lib/`, `test/`, `android/`, `ios/`, `web/` trees, the full `backend/` (migrations, src, tests, Dockerfile, openapi.yaml), `assets/` and `pics/` (logo art), docs, and this handover file itself. What's still intentionally untracked (build output, caches): `.dart_tool/`, `/build/`, `android/.gradle/`, `backend/node_modules/`, `.idea/`.

**Not yet done:** no remote configured (no GitHub/GitLab push target set up), no `.gitattributes`, no branch protection or CI. The repo is purely local at this point. Decide on a remote and hosting (GitHub vs GitLab vs private) in a future session if the project is meant to be shared or backed up off this machine.

## 2026-10-08 session (continued) — driver booking accept/decline

The biggest gap flagged earlier this session — drivers having no way to approve or reject a seat request, with bookings auto-confirming on `requestSeat` — is now closed, reusing existing schema and admin logic rather than inventing new patterns.

### What was discovered that changed the scope

The reservations schema (`001_initial.sql`) already had `requested`/`confirmed`/`cancelled`/`expired` states, and **the admin console already has a working confirm/cancel implementation** (`AdminService.confirmBooking`/`cancelBooking`, `POST /v1/admin/bookings/:id/(confirm|cancel)`) — it was just admin-only, with no ownership check (an admin can act on any booking) and no driver-facing route. This meant the real gap was much smaller than initially scoped: no migration was needed, and the transactional logic to copy was already proven in production-shaped code. The new driver endpoints are the same logic plus a `driver_id` ownership check the admin path doesn't need.

### Backend changes

- `postgres-trip-repository.js` / `in-memory-trip-repository.js`: added `listDriverPendingReservations({ driverId })`, `confirmDriverReservation({ reservationId, driverId })`, `declineDriverReservation({ reservationId, driverId })`. Each confirm/decline call verifies the reservation's trip actually belongs to `driverId` before mutating anything — querying by `reservationId` alone would let any driver act on anyone's booking, which is exactly the bug class the admin path doesn't have to guard against (admins are allowed to touch any booking by design).
- `trip-service.js`: added `listDriverReservations`, `confirmReservation`, `declineReservation`, all gated by `requireRole(actor, 'driver', 'trips:manage_own')` — reusing the permission drivers already hold, no new permission added to the RBAC migrations.
- `http-server.js`: added `GET /v1/driver/reservations`, `POST /v1/driver/reservations/:id/confirm`, `POST /v1/driver/reservations/:id/decline`.
- Declining a reservation releases its held seat back to the trip (mirrors passenger self-cancellation); confirming does not change seat inventory (seats were already decremented at request time — confirming only changes status and notifies the passenger).
- Tests added: `trip-permissions.test.js` (role/permission denial for all three new service methods) and `api.test.js` (full HTTP round trip: list → confirm → decline, plus — the one that actually matters — **a driver cannot confirm or decline another driver's reservation**, asserted as a 404, and a passenger cannot call the driver-only routes at all, asserted as a 403). All 47 backend tests pass (`npm run check`).

### Flutter changes

- `TripRepository` interface: added `pendingDriverReservations` getter, `confirmReservation(Booking)`, `declineReservation(Booking)`.
- `InMemoryTripRepository` (mock mode): implemented using the same local list-mutation style as the existing `cancelBooking`.
- `LocalApiTripRepository`: implemented against the three new endpoints above; `_loadAll` now also fetches `/v1/driver/reservations` when the signed-in role is `driver` (mirrors the existing `driverTripSummaries` fetch pattern).
- `DriverHomeScreen`: added a "Seat requests" section (only rendered when `pendingDriverReservations` is non-empty) with Accept/Decline buttons per pending booking, above "Your posted rides". Errors surface via the same `StateError` → `SnackBar` pattern used elsewhere in the app (`PostTripScreen`, `TripTrackingScreen`).
- Tests added: a repository-level test (`widget_test.dart`) exercising the full accept/decline state machine directly against `InMemoryTripRepository`, and a widget-level test (`admin_test.dart`) that renders the actual driver dashboard, taps "Accept", and asserts the booking's status changes and the section disappears once there's nothing pending. (The widget test needed a larger `tester.view.physicalSize` — the default test viewport was too small for the button to be hit-testable without scrolling; noting this in case the pattern is needed again for other dashboard widget tests.) All 42 Flutter tests pass (`flutter test`); `flutter analyze` is clean.

### Explicit non-goals / still open

- No push notification or real-time update when a driver confirms/declines — the passenger finds out via the existing in-app notification list (`/v1/me/notifications`), which already worked before this change; nothing new was needed there since `createNotification` was reused as-is.
- No UI anywhere shows a passenger their booking is specifically "awaiting driver approval" vs. "confirmed" with different visual treatment — ~~`trip_tracking_screen.dart`'s `_BookingCard` still only distinguishes...~~ **Fixed in this same session, same commit:** `_BookingCard` now shows three distinct states — "Awaiting driver" (requested, green), "Confirmed" (confirmed, green), "Cancelled" (anything else, gray) — instead of the binary requested/cancelled treatment that would have mislabeled a newly-confirmed booking as cancelled. The "Cancel ride" and "View" buttons remain gated on `requested` only, unchanged, since the backend only allows a passenger to self-cancel a still-pending request.
- Still no payments, so "confirm" has no monetary meaning yet — it is purely a status change.

## 2026-10-08 session (continued again) — direct driver-to-passenger mobile money payment

### Explicit model, chosen by the user, not inferred

There is **no platform-held wallet or payment processor integration**. A passenger pays the driver's mobile money number **directly**, outside the app (e.g. via USSD or the network's own app), then **both sides self-report** the outcome in YɛnKɔ:
- Passenger marks "I've paid" after sending money.
- Driver marks "I've received this payment" after checking their own MoMo balance/SMS.

**Neither report is verified against any provider.** This has no fraud protection by design — a passenger could falsely mark paid, or a driver could deny a real payment, and the app cannot tell. This tradeoff was explicitly chosen (no central payment collection) rather than discovered as a limitation; it is the correct scope for this stage, not a shortcut.

This was deliberately *not* built as even a partial/fake integration with a real payment processor (Paystack, MTN MoMo direct, etc.) since that would require a merchant account, API credentials, and a public webhook endpoint — none of which exist, and faking any part of that would be actively misleading about what the app does with money.

### Schema (migration 011)

- `users.momo_number`, `users.momo_network` (`mtn`/`telecel`/`airteltigo`) — a driver's own payout number, self-registered, never verified.
- `reservations.payment_status` (`unpaid` default / `passenger_marked_paid` / `driver_confirmed_received`) — independent of `reservations.status` (`requested`/`confirmed`/`cancelled`), since payment and seat-confirmation are different lifecycles that happen to usually follow each other.
- Two new permissions, granted by default to the existing system groups rather than overloading `view_own`/`cancel_own`/`manage_own` (those are semantically about viewing/cancelling/managing, not payment reporting): `reservations:report_payment` (Riders) and `trips:confirm_payment` (Drivers).

### Backend

- `user.js`: `momoNetworks`, `isValidMomoNumber`.
- `postgres-user-repository.js` + in-memory fixture: `setMomoDetails`.
- `auth-service.js`: `setMomoDetails` (role-checked driver-only via `rolesForUser`, not just the primary role, since a multi-role account could technically also be a passenger), `getMomoDetails`.
- `http-server.js`: `GET`/`PUT /v1/me/momo`.
- `postgres-trip-repository.js` / `in-memory-trip-repository.js`: `payment_status` threaded through **every** reservation read and write path (this took several passes to get right — the column needed adding to every `SELECT`/`RETURNING` clause that ultimately feeds `#toReservation`, not just the new ones). Added `listDriverConfirmedReservations`, `markPaymentSent` (passenger-owned-booking check), `markPaymentReceived` (driver-owned-trip check). A confirmed booking's response carries the driver's `momoNumber`/`momoNetwork` **only when `status === 'confirmed'`** — deliberately not exposed on open/pending trips, so a browsing or not-yet-accepted passenger can't see where to pay before the driver has actually agreed to take them.
- `trip-service.js`: `listDriverConfirmedReservations`, `markPaymentSent` (requires `passenger` role + `reservations:report_payment`), `markPaymentReceived` (requires `driver` role + `trips:confirm_payment`). `toBookingResponse` now passes through `paymentStatus` and `driverMomo` — this was a real bug caught by the first attempt at an integration test (the repository returned the data correctly, but the service-layer DTO mapper was silently dropping both fields).
- `http-server.js`: `GET /v1/driver/reservations/confirmed`, `POST /v1/me/reservations/:id/mark-paid`, `POST /v1/driver/reservations/:id/mark-received`.
- **Test infrastructure gap found and fixed**: the existing `api.test.js` harness (`DevelopmentActorResolver`, header-based dev actors) has no `AuthService` at all, so it structurally cannot exercise `/v1/me/momo` or anything else that depends on real user accounts. Wrote a new `backend/test/momo-payment.test.js` with its own full in-memory stack (`InMemoryUserRepository` + `InMemoryTripRepository` + real `AuthService` + `LocalAuthActorResolver`, no Postgres) — the first test file in this repo to combine all of those without a real database. Also found and fixed that the shared `InMemoryUserRepository` test fixture's seeded `Riders`/`Drivers` groups had **empty permission lists**, unlike the real migration 009 defaults, which silently passed for every prior test only because none of them exercised `TripService`'s permission checks through a real signed-up account; now seeded to match production defaults.
- All 51 backend tests pass (`npm run check`), including: registering/clearing a payout number, rejecting an invalid number, a non-driver being refused (403), the full confirm→mark-paid→mark-received happy path, idempotent replay of mark-paid, and — the properly load-bearing test — **neither a different passenger nor a different driver can self-report payment on someone else's booking** (404 both ways).

### Flutter

- `Booking` gained `paymentStatus` (default `unpaid`) and `driverMomo` (`DriverMomo?`, null until confirmed); new `DriverMomo` value type with a `networkLabel` getter for display ("MTN MoMo" etc.).
- `TripRepository` interface gained `confirmedDriverReservations`, `myMomoDetails`, `setMomoDetails`, `markPaymentSent`, `markPaymentReceived`, implemented in both `InMemoryTripRepository` and `LocalApiTripRepository`. The in-memory repository's `confirmReservation` now attaches the signed-in mock driver's own `_myMomo` onto a freshly confirmed booking, since mock mode has no separate user-lookup concept.
- `ProfileScreen`: new `_MomoPayoutCard` in the driver-mode section — view/edit/clear a payout number with network selection (MTN/Telecel/AirtelTigo chips), inline validation errors surfaced via `StateError` → `SnackBar`, consistent with every other form in this app.
- `trip_tracking_screen.dart`: new `_PaymentSection`, shown on a confirmed booking only when `driverMomo != null` — shows "Pay {network} {number} directly", an explicit "YɛnKɔ does not collect this payment" disclaimer, and an "I've paid" button that transitions through `unpaid` → `passenger_marked_paid` → (driver confirms) → `driver_confirmed_received`, with distinct copy at each state.
- `driver_home_screen.dart`: new "Payments to confirm" section (only rendered when a confirmed booking's payment isn't yet `driver_confirmed_received`), each card showing whether the passenger has self-reported paying yet, with an "I've received this payment" action. Class doc comment updated — it previously said "no accept/decline queue" from an earlier point in this same session, which was already stale after that feature shipped.
- Tests: `widget_test.dart` gained repository-level tests for `setMomoDetails` validation and the full confirm→payment-self-report state machine; `admin_test.dart` gained a widget-level test that renders the real driver dashboard, taps "I've received this payment", and asserts the section disappears and `paymentStatus` updates. 45/45 Flutter tests pass; `flutter analyze` clean.

### Explicit non-goals / still open

- No real payment verification of any kind — restated because it is the single most important thing to not lose track of about this feature. If real money handling is wanted later, that is a materially different, much larger piece of work (merchant account, processor integration, webhook, settlement) — not an upgrade of this flow.
- No dispute resolution UI if the two sides disagree (passenger says paid, driver says not received, or vice versa) — the data model can represent the disagreement (`payment_status` just stops advancing), but nothing surfaces it as a flagged case anywhere, including the admin console.
- A driver can have at most one payout number for all their trips (no per-trip override) — matches how real drivers actually operate (one personal MoMo line), not flagged as a gap.
- `markPaymentSent`/`markPaymentReceived` have no time limit — a booking's payment can be self-reported at any point after confirmation, with no reminder or expiry.

## 2026-10-08 session (continued yet again) — biometric login, ported from onb

User asked to replicate onb's GPS tracking and biometric login features. Investigated both via subagents before touching code; biometrics went first (smaller, no missing external dependency — GPS needs a fresh Google Maps API key from the user, not yet provided).

### What was already there vs. what was missing

Native Android/iOS biometric unlock was **already fully built and correctly configured** in ynk before this session — `local_auth: 3.0.2` in pubspec, `MainActivity.kt` already extending `FlutterFragmentActivity`, `USE_BIOMETRIC` already in the Android manifest, `NSFaceIDUsageDescription` already in `Info.plist`, and `BiometricService` already wired into both the login screen and profile screen. This was wrongly assumed to be missing before actually reading the code — a reminder that "replicate X" first needs confirming X doesn't already exist. Only `USE_FINGERPRINT` (a legacy Android permission, redundant on modern Android but harmless) was missing for full parity with onb, and was added.

**One real pre-existing bug was found and fixed in the process**: `local_login_screen.dart`'s `_biometricSignIn` called `BiometricService.enable()` (which re-prompts the one-time enrollment ceremony AND re-persists the "enabled" flag) on **every** biometric sign-in attempt, instead of only the first time. `BiometricService` had no plain `authenticate()` method to call instead for repeat use. Added one (`authenticate({reason})` — prompts without touching the enrollment preference, returns `false` immediately without prompting if biometrics are disabled/unavailable) and fixed the login screen to call `enable()` only the first time and `authenticate()` on every subsequent sign-in.

**The actual gap versus onb was the PWA/web WebAuthn (passkey) flow** — onb's biggest biometric-related addition, entirely absent from ynk. Native biometrics in ynk needed no porting at all; they were already equivalent to or better than onb's (ynk's native flow never caches the raw password in secure storage the way onb's does — it only replays what's currently typed in the form after a device check, which is a smaller trust surface).

### What was built (WebAuthn / PWA passkeys)

Unlike native biometric unlock (purely client-side device-lock, server never involved), a PWA has no OS-level secure storage to cache a password in, so this is a different mechanism entirely: real WebAuthn passkeys, verified server-side.

**Flutter:**
- `lib/core/security/webauthn/webauthn_bridge.dart` (contract), `webauthn_bridge_stub.dart` (non-web no-op), `webauthn_bridge_web.dart` (real browser implementation via `dart:js_interop` + `package:web: ^1.1.0`) — ported near-verbatim from onb, renamed to ynk's conventions. Selected via the same conditional-import pattern already used for `biometric_backend_io/web.dart`. Verified compiling on both the native/VM analyze target and an actual `flutter build web`.
- `LocalAuthClient` gained `webAuthnRegistrationOptions`, `webAuthnRegistrationVerify`, `webAuthnAuthenticationOptions`, `webAuthnAuthenticationVerify` (returns a full `LocalAuthSession` — a successful assertion *is* the sign-in), `webAuthnStatus`, `webAuthnDeleteCredential`.
- `BiometricService` extended with the web-only passkey flows (`registerWebAuthn`, `authenticateWebAuthn`), an `authClient` reference set once by `main.dart`, and `rememberAccessTokenForWebAuthnSetup` (registration needs a bearer token; authentication does not, since no account is known yet before the assertion). `initialize()` now checks WebAuthn platform-authenticator availability on web instead of always reporting unavailable.
- `local_login_screen.dart`: a "Sign in with a passkey" button on web (branches on `kIsWeb` from the same UI slot the native biometric button already occupied), calling `authenticateWebAuthn()` directly — no username/password typed first, unlike the native replay flow.
- `profile_screen.dart`: the existing biometric `SwitchListTile` now branches on `kIsWeb` — "enable" registers a new passkey (`registerWebAuthn`) instead of toggling a device preference; copy changes from "Face ID or fingerprint" to "passkey" language on web. `ProfileScreen` gained an `accessToken` parameter (threaded from `YenkoRootScreen`'s `session.accessToken`) since passkey registration needs it.

**Backend:**
- Migration 012: `webauthn_credentials` (credential ID, public key, counter, device type, backed-up flag, transports, optional device label) and `webauthn_challenges` (short-lived server-issued challenges, consumed exactly once, same pattern as `otp_codes`).
- New dependency: `@simplewebauthn/server` 14.0.3 (pinned exact version, MIT, actively maintained — the same library onb uses).
- `PostgresWebAuthnRepository`: credential CRUD, challenge issuance/consumption.
- `WebAuthnService` (new application-layer class, not folded into `AuthService`): `registrationOptions`/`registrationVerify` (requires an existing session — registering a passkey for an already-authenticated account), `authenticationOptions`/`authenticationVerify` (no session required — the assertion itself identifies and authenticates the account, then calls a new `AuthService.issueSessionForUserId` to mint a real session), `status`, `deleteCredential`.
- Routes: `POST /v1/auth/webauthn/register/options`, `POST /v1/auth/webauthn/register/verify` (both require an existing session), `POST /v1/auth/webauthn/authenticate/options`, `POST /v1/auth/webauthn/authenticate/verify` (both public — no account known yet), `GET /v1/auth/webauthn/status`, `DELETE /v1/auth/webauthn/credentials/:id`.
- Dark until configured: `WEBAUTHN_RP_ID` and `WEBAUTHN_ORIGIN` env vars (documented in `.env.example`) are both required or the whole feature is simply absent from the running server (`webauthnService` stays undefined, routes 404) — same "additive, opt-in by config" pattern as the social-login providers.
- Tests: `backend/test/webauthn-service.test.js`, 10 new unit tests against an in-memory repository double (challenge issue/consume-once, unknown-user/unknown-credential rejection, malformed-response rejection, per-user credential isolation for `status`/`deleteCredential`, and a sanity check that the underlying `@simplewebauthn/server` functions are callable). **Not covered**: SQL correctness of `PostgresWebAuthnRepository` itself — that needs the Postgres-backed integration suite (gated on `TEST_DATABASE_URL`, not available in this environment) and should be added before relying on this in production. 61/61 backend tests pass overall.

### Explicit non-goals / still open

- No "straight to biometric" conditional-UI autofill ceremony (onb has `isConditionalMediationAvailable`/`getAssertionConditional`/`primePasskeyAutofill` wired into the login form's text field autocomplete; ynk's bridge *implements* these methods — ported verbatim — but nothing in the login screen calls them yet). The explicit "Sign in with a passkey" button covers the core feature; the autofill polish is a smaller follow-up.
- No UI to list/remove individual registered passkeys on the profile screen yet (`webAuthnStatus`/`webAuthnDeleteCredential` exist on the client and backend, just not surfaced in a widget) — flagged as a near-term follow-up, not done this session since the core register/sign-in loop was the priority.
- `PostgresWebAuthnRepository` has no automated test coverage against a real database in this environment (see above) — the SQL itself was written carefully against the existing schema conventions in this codebase, but has not been run against Postgres.
- `WEBAUTHN_RP_ID`/`WEBAUTHN_ORIGIN` must exactly match the real deployed PWA's domain or every ceremony will fail verification (this is WebAuthn's own security model, not a bug) — whoever deploys this needs to set these correctly, there is no sensible default.

## 2026-10-09 session — live GPS location tracking (backend + web/OSM path), ported from onb

Second half of the biometrics-then-GPS request. Replicated onb's live location feature, adapted to a real architectural difference: onb's `Trip` has exactly one driver and one rider, so onb stores live fields on the trip row directly. A YɛnKɔ trip can have several confirmed bookings/passengers at once, so the live columns live on `reservations` instead — the driver's position is the same for every passenger riding with them, so a single location post updates every confirmed booking on that trip at once. There is no websocket layer, matching onb: the rider's app polls every 5 seconds, same as onb's `rider_tracking_screen.dart`.

This session covers the backend and the web/PWA map path (flutter_map + OpenStreetMap, no API key needed) end to end. **Native Google Maps rendering is deferred** — it needs a fresh Google Maps API key for ynk that the user has not yet provided (explicitly agreed not to reuse onb's key). Everything else — GPS streaming, permission handling, the backend, and the rider-facing map — works today on web; native Android/iOS can share and read location the same way, just without a native map widget to show it on yet (see below for the native gap this leaves).

### Backend

- Migration 013: `live_latitude`, `live_longitude`, `live_speed_kmh`, `live_heading`, `live_updated_at` added to `reservations` (not `trips` — see above), with range CHECK constraints. New permission `trips:share_location`, granted to the `Drivers` system group only; reading piggybacks on the existing `reservations:view_own` a passenger already has.
- `domain/trip.js`: `validateLiveLocation` — latitude/longitude required and range-checked, speed/heading optional.
- `TripService.updateLiveLocation({ actor, tripId, input })` — driver-only, posts one fix to every confirmed booking on the trip at once. `TripService.getLiveLocation({ actor, reservationId })` — passenger-only, returns the fix last recorded for their own booking (nulls if the driver has not shared yet, not an error).
- `PostgresTripRepository`/`InMemoryTripRepository`: `updateLiveLocation` (single `UPDATE ... WHERE trip_id = $1 AND status = 'confirmed'`, inside a transaction with a `FOR UPDATE` lock on the Postgres side to confirm trip ownership first) and `getLiveLocation` (ownership-scoped read).
- Routes: `POST /v1/driver/trips/:tripId/location`, `GET /v1/me/reservations/:id/location`.
- `test/live-location.test.js`: 3 new end-to-end tests against the full in-memory stack — posting before any confirmed booking exists is rejected (409), a rider sees nulls before the first fix and the real fix after, cross-account access is rejected (404) in both directions (another driver cannot post to this trip, another passenger cannot read this booking). 64/64 backend tests pass overall.

### Flutter

- New dependencies: `geolocator ^13.0.2`, `flutter_map ^7.0.2` + `latlong2 ^0.9.1` (OpenStreetMap tiles, no API key — this is the only map path built so far), `wakelock_plus ^1.2.8`, `url_launcher ^6.2.5` (added for the Android `<queries>` https/geo intent handoff below; not yet called from anywhere — see gaps).
- `core/models/trip.dart`: `LiveLocation` (nullable fields, `hasFix` getter).
- `TripRepository` interface + both implementations gained `shareLiveLocation` (driver) and `fetchLiveLocation` (passenger).
- `features/live_map/live_location_tracker.dart`: `LiveLocationTracker` wraps `Geolocator.getPositionStream`, throttles backend posts to once every 5 seconds (matches onb), and runs a 20-second permission watchdog that fires a callback if no fix arrives at all (likely a silently broken permission/service state) so the UI can tell the driver to check their settings instead of waiting forever. The actual speed math is pulled out into a standalone `resolveSpeedKmh` function (unit tested in `test/live_location_tracker_test.dart`, 5 tests) implementing onb's computed-speed fallback: Android often reports exactly 0 m/s even while moving at low speed, so when that happens this falls back to distance-travelled-since-the-last-fix ÷ elapsed time, with a 180 km/h cap to reject GPS-jitter spikes between close-together fixes.
- `features/live_map/live_location_map.dart`: `LiveLocationMap`, a flutter_map widget showing the driver's position and heading on OpenStreetMap tiles — this is the only map rendering built so far, works on every platform including web, and needs no API key.
- `features/live_map/driver_tracking_screen.dart`: start/stop sharing for one trip, shows the last fix and any permission/sharing error inline.
- `features/live_map/rider_tracking_screen.dart`: polls every 5 seconds, shows the OSM map once a fix exists, a waiting state before the driver starts sharing, and the last-updated age.
- Entry points: a "Share live location" button on each active trip card in `DriverHomeScreen` (shown only once that trip has at least one confirmed booking); a new "Track" button on a confirmed booking's card in `TripTrackingScreen` (left the existing, unrelated "View" button on pending requests untouched — it was already a dead placeholder before this session, out of scope to fix here).
- Android manifest: added the 6 location/foreground-service/wake-lock permissions and `<queries>` entries for https/geo intent handoff (for a future "open in maps app" action — url_launcher is installed for this but not yet called anywhere, see gaps). Deliberately did **not** add a `com.google.android.geo.API_KEY` meta-data tag — there is no key yet and no native map view that would need one.
- iOS Info.plist: added `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, and `UIBackgroundModes: [location]`. This is a deliberate improvement over onb, which has no iOS location permissions declared at all (confirmed during research, not an oversight to replicate — see the 2026-10-08 session's biometric research notes for context on where that finding came from).

### Explicit non-goals / still open

- **Native Google Maps rendering is not built.** `LiveLocationTracker`/`shareLiveLocation`/`fetchLiveLocation` work identically on every platform (they're pure Dart + HTTP + the geolocator plugin), but the only *map widget* is the OSM one, which this session treated as the universal path rather than a web-only fallback. Once the user provides a fresh Google Maps API key, add `google_maps_flutter`, branch the map widget on `kIsWeb` (OSM) vs native (Google Maps), and add the Android manifest's `API_KEY` meta-data tag plus `GMSApiKey` on iOS, following onb's `navigation_launcher.dart` branching pattern.
- No turn-by-turn navigation handoff ("open in Google Maps/Apple Maps") wired up yet — `url_launcher` is installed and the Android manifest's `<queries>` entries are in place for it, but nothing calls it. A reasonable follow-up button on `RiderTrackingScreen`/`DriverTrackingScreen`.
- No ETA or ride-progress calculation (onb's tracking screens compute an ETA from the live fix to the destination; not ported this session — this was a secondary feature in onb's screens and the user's priority was get sharing/viewing working first).
- No ride-start/ride-end lifecycle. "Sharing" is purely a manual start/stop toggle on `DriverTrackingScreen`, not tied to the trip's own status transitions (`trips.status` is still only `open`/`cancelled`/`completed` in this schema — see the `_statusFromApi` note in `lib/core/models/trip.dart`, which maps `in_progress`/`confirmed`/`requested` trip statuses the current backend never actually produces). A later pass could tie "start sharing" to a real "trip started" transition if that becomes a desired feature in its own right.
- Live location is not geofenced to stop automatically on arrival (onb has a haversine-based geofence stop detection in its backend `tracking.service.ts`) — not ported this session; the driver must manually press "Stop sharing".
- `LiveLocationTracker`'s permission watchdog and the Android `AndroidSettings` foreground-notification config have not been exercised on a real device in this environment (no physical Android/iOS hardware or working emulator available here) — only `flutter analyze`/`flutter test`/`flutter build web` were run. Treat the on-device GPS streaming path as implemented-but-unverified-on-hardware until someone runs it on an actual phone.



## Suggested future-session prompt

> Continue YɛnKɔ from `/Users/andrewstardie/Documents/TUTS/TESTS/ynk/YɛnKɔ`. Read `HANDOVER.md` first in full. First confirm an actual sign-in through the PWA's browser UI (the boot-crash was fixed and verified error-free, but a real click-through login was not). The real logo is `assets/app/yenko_logo.png` — delete the leftover FaMe-branded `assets/yenko-logo-lockup-preview.png` if you touch assets. The admin console, RBAC, and email/social auth backend are all real and substantially complete — read the "What changed" section before assuming anything is a stub; the actual remaining stubs are: mail/SMS delivery (console-only, `devCode` leak), and the native social-login SDKs on the Flutter side (server-side verification is real for Google/Apple/Facebook/X). This project has no git history — initializing one is overdue and should be treated as a priority, not deferred further. Always sanity-check claims in this file by reading the actual source before building on them, the way the last two handovers each had errors that only surfaced on re-investigation.
