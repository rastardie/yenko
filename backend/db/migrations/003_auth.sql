-- Real phone + PIN authentication for YɛnKɔ, additive to the existing minimal
-- `users` table (id, display_name). Mirrors the Onboard app's proven model
-- (bcrypt PIN hash, per-session JWT with revocation, auth_version bump to
-- invalidate tokens, group-derived roles) adapted to YɛnKɔ's simpler
-- passenger/driver/admin role set and plain-Node backend.

ALTER TABLE users
  ADD COLUMN phone TEXT UNIQUE,
  ADD COLUMN username TEXT UNIQUE,
  ADD COLUMN phone_verified BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN pin_hash TEXT,
  ADD COLUMN must_change_pin BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN auth_version INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'suspended', 'pending'));

CREATE INDEX users_phone_idx ON users (phone) WHERE phone IS NOT NULL;
CREATE INDEX users_username_idx ON users (username) WHERE username IS NOT NULL;

-- Role is derived from group membership (not stored directly on users), so an
-- access change takes effect on next request rather than waiting for a new
-- token. Default groups seeded below give every signup the "passenger" role.
CREATE TABLE groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE CHECK (char_length(name) BETWEEN 1 AND 80),
  role TEXT NOT NULL CHECK (role IN ('passenger', 'driver', 'admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO groups (name, role) VALUES
  ('Passengers', 'passenger'),
  ('Drivers', 'driver'),
  ('Admins', 'admin');

CREATE TABLE group_members (
  group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE INDEX group_members_user_idx ON group_members (user_id);

-- One row per issued session/device. Revoking a row (or bumping
-- users.auth_version) invalidates the matching JWT immediately, even though
-- the token itself remains cryptographically valid until it expires.
CREATE TABLE auth_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_activity_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX auth_sessions_user_idx ON auth_sessions (user_id);

-- Short-lived codes for phone verification and PIN reset. codeHash is bcrypt,
-- never the raw code; attempts is capped by the application layer.
CREATE TABLE otp_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  purpose TEXT NOT NULL CHECK (purpose IN ('phone_verification', 'pin_reset')),
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX otp_codes_user_purpose_idx ON otp_codes (user_id, purpose, created_at DESC);
