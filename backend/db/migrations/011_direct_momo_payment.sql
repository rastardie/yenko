-- Direct driver-to-passenger mobile money payment, self-reported only.
--
-- There is no platform-held wallet and no payment processor integration.
-- A passenger pays the driver's mobile money number directly (MTN MoMo,
-- Telecel Cash, or AirtelTigo Money, outside the app, e.g. via USSD or the
-- network's own app), then both sides self-report the outcome in YɛnKɔ.
-- Neither report is verified against any provider — this is an honesty-based
-- confirmation flow, not a payment integration. See HANDOVER.md for the
-- rationale and limitations.

ALTER TABLE users
  ADD COLUMN momo_number TEXT,
  ADD COLUMN momo_network TEXT CHECK (momo_network IN ('mtn', 'telecel', 'airteltigo'));

-- A loose phone-shaped check, consistent with the existing `phone` column's
-- lack of strict E.164 enforcement at the DB layer (validation lives in the
-- application layer, same as elsewhere in this schema).
ALTER TABLE users
  ADD CONSTRAINT users_momo_number_format
    CHECK (momo_number IS NULL OR momo_number ~ '^\+?[0-9]{9,15}$');

ALTER TABLE reservations
  ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'unpaid'
    CHECK (payment_status IN ('unpaid', 'passenger_marked_paid', 'driver_confirmed_received'));

-- A passenger self-reporting "I paid" and a driver self-reporting "I was
-- paid" are new, distinct actions from booking/cancelling a seat, so they
-- get their own permission keys rather than overloading view_own/cancel_own
-- or trips:manage_own. Granted by default to the same system groups that
-- already hold the sibling reservation/trip permissions (Riders, Drivers).
INSERT INTO permissions (resource, action, description) VALUES
  ('reservations', 'report_payment', 'Mark your own confirmed booking as paid (self-reported, not verified)'),
  ('trips', 'confirm_payment', 'Mark a payment received on your own trip (self-reported, not verified)');

INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON (g.role = 'passenger' AND (p.resource, p.action) = ('reservations', 'report_payment'))
  OR (g.role = 'driver' AND (p.resource, p.action) = ('trips', 'confirm_payment'))
WHERE g.is_system;
