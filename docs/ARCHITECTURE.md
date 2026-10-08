# YɛnKɔ architecture baseline

## Decision

YɛnKɔ is being evolved as an API-first modular monolith: a Flutter client consumes a versioned HTTP contract; domain use cases depend on ports; infrastructure adapters supply identity, persistence, provider integrations, and operations. The backend persists to PostgreSQL and is run locally; it is not deployed anywhere yet.

## Current implemented boundary

`backend/` contains four layers:

1. **Domain**: validation, roles and permission helpers, public-response minimization, typed errors.
2. **Application**: trip discovery, fixed-price trip publishing, idempotent seat requests and cancellation, authentication (`AuthService`) and administration (`AdminService`).
3. **Infrastructure**: PostgreSQL repositories (trips, users, admin), actor resolvers (local JWT, OIDC, development header), migrations.
4. **Interfaces**: native HTTP adapter, the `/v1/admin/*` router, health endpoints and the OpenAPI contract (`backend/openapi.yaml`).

Identity in local development is `local-pin`: bcrypt-hashed password and quick PIN, JWT sessions that can be revoked, and group membership that yields the role and the admin permissions on every request. The Flutter app talks to the API through `TripRepository` (mock or local API), `LocalAuthClient` and `AdminApiClient`, and only uses the published contract.

## Required production substitutions

| Boundary | Required replacement | Non-negotiable property |
|---|---|---|
| Identity | Selected OIDC provider and server-side JWT/JWKS verification; port the group/permission model and admin API to it | No client-controlled roles or headers |
| Data | PostgreSQL with migrations and transactional locking | Atomic seat holds and durable idempotency keys |
| Secrets | AWS Secrets Manager or SSM Parameter Store | No credentials in app, images, or manifests |
| Operations | Structured logs, traces, metrics, audit events, alerting | Correlation IDs and privacy-safe logging |
| Edge | TLS, WAF/rate limiting, request-size controls | No direct public database access |
| Async work | Queue/outbox pattern | Provider callbacks and notifications are retry-safe |

## Explicitly deferred integrations

No maps, precise/background location, payments, Ghana Card/DVLA verification, chat, notifications, analytics, or emergency workflows are coded. Each needs provider selection, consent/retention rules, security review, operational playbooks, and Ghana-specific legal/compliance approval.

## Deployment target after substitutions

Use a dedicated namespace, non-root/read-only containers, dropped capabilities, probes, requests/limits, NetworkPolicies, IRSA, and managed PostgreSQL. The local-development authentication mode (`local-pin`) and its seed accounts must never be deployed as a production workload.
