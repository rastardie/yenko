-- Email and social sign-in for YɛnKɔ. Authentication methods (email/password,
-- Google, Apple, Facebook, X) are decoupled from the account: one user may link
-- several. Social providers never supply a trustworthy legal name, so the legal
-- name is collected separately and, for now, is self-attested. Username + PIN
-- continues to work unchanged; a username is mandatory for social signups.

-- One row per linked sign-in method. provider_uid is the provider's stable
-- subject identifier (NOT the email, which can change or be hidden).
CREATE TABLE auth_identities (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider       TEXT NOT NULL
    CHECK (provider IN ('password', 'google', 'apple', 'facebook', 'twitter')),
  provider_uid   TEXT NOT NULL,
  email          TEXT,
  email_verified BOOLEAN NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_uid)
);

CREATE INDEX auth_identities_user_idx ON auth_identities (user_id);

-- Email becomes a first-class login identity alongside phone and username.
-- Legal name is kept apart from the friendly display_name and marked with how
-- it was obtained; id_verified stays false until a document/NIA check is added.
ALTER TABLE users
  ADD COLUMN email TEXT UNIQUE,
  ADD COLUMN email_verified BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN legal_surname TEXT,
  ADD COLUMN legal_given_names TEXT,
  ADD COLUMN legal_name_source TEXT NOT NULL DEFAULT 'self_attested'
    CHECK (legal_name_source IN ('self_attested', 'id_document', 'nia_verified')),
  ADD COLUMN id_verified BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX users_email_idx ON users (email) WHERE email IS NOT NULL;

-- Allow email verification codes to reuse the existing otp_codes machinery.
ALTER TABLE otp_codes DROP CONSTRAINT otp_codes_purpose_check;
ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_purpose_check
  CHECK (purpose IN ('phone_verification', 'pin_reset', 'email_verification'));
