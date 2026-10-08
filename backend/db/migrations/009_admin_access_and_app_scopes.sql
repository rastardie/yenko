-- Permission scope for every group.
--
-- * admin:access decides who sees and may call the Admin area. By default only
--   the Super Admins and Admins groups hold it, so Operators, Support Agents,
--   Finance and Fleet Managers keep their scopes but have no Admin menu until
--   an administrator ticks "Open the Admin area" on their group.
-- * The rider and driver app actions become permissions too, so Drivers and
--   Riders have a real, editable scope instead of an empty one:
--     Drivers: trips:offer, trips:manage_own
--     Riders:  reservations:book, reservations:cancel_own, reservations:view_own
--   The trip API enforces these in addition to the account's role.

INSERT INTO permissions (resource, action, description) VALUES
  ('admin', 'access', 'Open the Admin area'),
  ('trips', 'offer', 'Offer and post trips as a driver'),
  ('trips', 'manage_own', 'See the bookings and status of your own trips'),
  ('reservations', 'book', 'Request seats on trips'),
  ('reservations', 'cancel_own', 'Cancel your own pending seat requests'),
  ('reservations', 'view_own', 'See your own bookings');

-- Super Admins hold every permission.
INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g CROSS JOIN permissions p
WHERE g.role = 'super_admin' AND g.is_system
  AND NOT EXISTS (
    SELECT 1 FROM group_permissions gp WHERE gp.group_id = g.id AND gp.permission_id = p.id);

-- Admins hold everything except the audit trail.
INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g CROSS JOIN permissions p
WHERE g.role = 'admin' AND g.is_system
  AND (p.resource, p.action) <> ('audit', 'read')
  AND NOT EXISTS (
    SELECT 1 FROM group_permissions gp WHERE gp.group_id = g.id AND gp.permission_id = p.id);

INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON (p.resource, p.action) IN (('trips', 'offer'), ('trips', 'manage_own'))
WHERE g.role = 'driver' AND g.is_system;

INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON (p.resource, p.action) IN
    (('reservations', 'book'), ('reservations', 'cancel_own'), ('reservations', 'view_own'))
WHERE g.role = 'passenger' AND g.is_system;
