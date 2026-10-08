-- 005 created an index on users(id) filtered by password_hash. Lookups are by
-- username/phone/id, so it was never used and only cost writes. 005 itself is
-- checksum-locked once applied, so it is dropped here instead of edited.
DROP INDEX IF EXISTS users_password_hash_idx;
