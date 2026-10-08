-- WebAuthn (passkey) credentials for the web/PWA client. Unlike native
-- biometric unlock (a purely client-side device-lock gating a cached
-- username/password, never seen by the server), a PWA has no OS-level
-- secure storage to cache a password in, so the browser's own WebAuthn API
-- is used instead and the server verifies every registration/authentication
-- ceremony with @simplewebauthn/server. See HANDOVER.md.

CREATE TABLE webauthn_credentials (
  id TEXT PRIMARY KEY, -- base64url credential ID, as returned by the browser
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  public_key BYTEA NOT NULL,
  counter BIGINT NOT NULL DEFAULT 0,
  device_type TEXT NOT NULL CHECK (device_type IN ('singleDevice', 'multiDevice')),
  backed_up BOOLEAN NOT NULL DEFAULT false,
  transports TEXT[] NOT NULL DEFAULT '{}',
  device_label TEXT CHECK (device_label IS NULL OR char_length(device_label) <= 120),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX webauthn_credentials_user_idx ON webauthn_credentials (user_id);

-- A short-lived server-generated challenge for an in-progress registration
-- or authentication ceremony. Expired rows are harmless (never read back
-- once past expires_at) and may be pruned by a future cleanup job; there is
-- no retention job yet, consistent with otp_codes/auth_sessions.
CREATE TABLE webauthn_challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT REFERENCES users(id) ON DELETE CASCADE, -- null during authentication before the user is known
  challenge TEXT NOT NULL,
  purpose TEXT NOT NULL CHECK (purpose IN ('register', 'authenticate')),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX webauthn_challenges_user_idx ON webauthn_challenges (user_id, purpose, created_at DESC);
