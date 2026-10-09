-- Live GPS location for a confirmed ride, self-reported by the driver's
-- device while a trip is under way.
--
-- Unlike onb (where a single Trip row has exactly one driver and one rider,
-- so live fields live on trips directly), a YɛnKɔ trip can have several
-- confirmed bookings/passengers at once. The driver's position is the same
-- for all of them, but "is this specific passenger's ride currently being
-- tracked" is naturally a property of their own confirmed reservation, not
-- the trip row — so the live columns go on `reservations`, and the driver's
-- app writes the same values to every one of their confirmed reservations
-- for a trip in a single update. There is no websocket layer here (same as
-- onb): the rider's app polls, same pattern already used for notifications.
ALTER TABLE reservations
  ADD COLUMN live_latitude DOUBLE PRECISION,
  ADD COLUMN live_longitude DOUBLE PRECISION,
  ADD COLUMN live_speed_kmh DOUBLE PRECISION,
  ADD COLUMN live_heading DOUBLE PRECISION,
  ADD COLUMN live_updated_at TIMESTAMPTZ;

ALTER TABLE reservations
  ADD CONSTRAINT reservations_live_latitude_range
    CHECK (live_latitude IS NULL OR live_latitude BETWEEN -90 AND 90),
  ADD CONSTRAINT reservations_live_longitude_range
    CHECK (live_longitude IS NULL OR live_longitude BETWEEN -180 AND 180),
  ADD CONSTRAINT reservations_live_speed_range
    CHECK (live_speed_kmh IS NULL OR live_speed_kmh BETWEEN 0 AND 300),
  ADD CONSTRAINT reservations_live_heading_range
    CHECK (live_heading IS NULL OR live_heading BETWEEN 0 AND 360);

-- A driver sharing their location is a new, distinct action from
-- confirming/declining a seat request or confirming payment, so it gets its
-- own permission key rather than overloading trips:manage_own. A rider
-- reading that location piggybacks on the existing reservations:view_own
-- permission they already hold to see their own bookings at all.
INSERT INTO permissions (resource, action, description) VALUES
  ('trips', 'share_location', 'Share live GPS location for your own trip while it is under way');

INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON g.role = 'driver' AND (p.resource, p.action) = ('trips', 'share_location')
WHERE g.is_system;
