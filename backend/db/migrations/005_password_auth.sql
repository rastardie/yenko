-- Username/password is the primary interactive sign-in credential. The
-- existing pin_hash column remains the separately supplied quick PIN value.
ALTER TABLE users
  ADD COLUMN password_hash TEXT;

CREATE INDEX users_password_hash_idx
  ON users (id)
  WHERE password_hash IS NOT NULL;
