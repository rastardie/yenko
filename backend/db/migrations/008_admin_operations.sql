-- Admin operations: approval, soft deletion, booking management and reports.
--
-- * users.status gains 'deleted' (soft delete). A deleted account keeps its id
--   and display name so trips, bookings and the audit trail stay intact, but its
--   username, phone and credentials are cleared so they can be reused.
-- * New permissions: users:approve, users:delete, reservations:manage,
--   reports:read.

ALTER TABLE users DROP CONSTRAINT users_status_check;
ALTER TABLE users ADD CONSTRAINT users_status_check
  CHECK (status IN ('active', 'suspended', 'pending', 'deleted'));
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMPTZ;

INSERT INTO permissions (resource, action, description) VALUES
  ('users', 'approve', 'Approve or deny accounts awaiting approval'),
  ('users', 'delete', 'Delete accounts'),
  ('reservations', 'manage', 'Confirm or cancel bookings'),
  ('reports', 'read', 'View and export booking reports');

-- Super Admins hold every permission.
INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g CROSS JOIN permissions p
WHERE g.role = 'super_admin' AND g.is_system
  AND (p.resource, p.action) IN (
    ('users', 'approve'), ('users', 'delete'), ('reservations', 'manage'), ('reports', 'read'));

-- Admins hold everything except the audit trail.
INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g CROSS JOIN permissions p
WHERE g.role = 'admin' AND g.is_system
  AND (p.resource, p.action) IN (
    ('users', 'approve'), ('users', 'delete'), ('reservations', 'manage'), ('reports', 'read'));

-- Operators run day-to-day operations and read reports.
INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON (p.resource, p.action) IN (('reservations', 'manage'), ('reports', 'read'))
WHERE g.role = 'operator' AND g.is_system;

-- Support can approve pending accounts and read reports.
INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON (p.resource, p.action) IN (('users', 'approve'), ('reports', 'read'))
WHERE g.role = 'support' AND g.is_system;

-- Finance and Fleet Managers read reports.
INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON (p.resource, p.action) IN (('reports', 'read'))
WHERE g.role IN ('finance', 'fleet_manager') AND g.is_system;
