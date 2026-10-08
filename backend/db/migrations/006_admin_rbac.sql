-- Administration model for YɛnKɔ, modelled on Onboard's group/permission
-- system and adapted to a ride-hailing operating structure (riders, drivers,
-- operations, support, finance, fleet, admins).
--
-- * `groups.role` is still the coarse application role a group grants.
-- * `permissions` / `group_permissions` grant fine-grained admin capabilities.
--   A user's effective permissions are the union over all their groups and are
--   evaluated on every request, so changes apply immediately.
-- * System groups are seeded here (not in seed.js) because they are reference
--   data that production also needs; seed.js only creates development users.

-- "Passengers" is renamed to "Riders" (the role value stays 'passenger').
UPDATE groups SET name = 'Riders' WHERE name = 'Passengers';

ALTER TABLE groups DROP CONSTRAINT groups_role_check;
-- Custom groups carry permissions only and therefore have no application role.
ALTER TABLE groups ALTER COLUMN role DROP NOT NULL;
ALTER TABLE groups ADD CONSTRAINT groups_role_check CHECK (
  role IS NULL OR role IN (
    'passenger', 'driver', 'super_admin', 'admin',
    'operator', 'support', 'finance', 'fleet_manager'
  )
);

ALTER TABLE groups
  ADD COLUMN description TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 300),
  ADD COLUMN is_system BOOLEAN NOT NULL DEFAULT false;

-- System groups are unique per role; it lets code find them by role.
CREATE UNIQUE INDEX groups_system_role_idx ON groups (role) WHERE is_system;

UPDATE groups SET is_system = true, description = 'Everyone who books seats on shared trips.'
  WHERE name = 'Riders';
UPDATE groups SET is_system = true, description = 'Drivers who publish trips and carry riders.'
  WHERE name = 'Drivers';
UPDATE groups SET is_system = true, description = 'Full administrators of users, groups, trips and dashboards.'
  WHERE name = 'Admins';

INSERT INTO groups (name, role, description, is_system) VALUES
  ('Super Admins', 'super_admin', 'Unrestricted access, including the audit trail and the Super Admins group itself.', true),
  ('Operators', 'operator', 'Live operations: monitor trips, cancel unsafe or failed trips.', true),
  ('Support Agents', 'support', 'Customer support: look up accounts and suspend or restore access.', true),
  ('Fleet Managers', 'fleet_manager', 'Driver and vehicle oversight. Vehicle permissions arrive with the vehicles module.', true),
  ('Finance', 'finance', 'Finance and reporting. Payment permissions arrive with the payments module.', true);

CREATE TABLE permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource TEXT NOT NULL CHECK (char_length(resource) BETWEEN 1 AND 40),
  action TEXT NOT NULL CHECK (char_length(action) BETWEEN 1 AND 40),
  description TEXT NOT NULL DEFAULT '',
  UNIQUE (resource, action)
);

CREATE TABLE group_permissions (
  group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (group_id, permission_id)
);

CREATE INDEX group_permissions_permission_idx ON group_permissions (permission_id);

INSERT INTO permissions (resource, action, description) VALUES
  ('users', 'read', 'View accounts and their groups'),
  ('users', 'create', 'Create accounts'),
  ('users', 'update', 'Edit account details'),
  ('users', 'manage_status', 'Suspend or restore accounts'),
  ('users', 'reset_credentials', 'Reset an account password'),
  ('groups', 'read', 'View groups, members and permissions'),
  ('groups', 'create', 'Create custom groups'),
  ('groups', 'update', 'Edit group details'),
  ('groups', 'delete', 'Delete custom groups'),
  ('groups', 'assign_members', 'Add or remove group members'),
  ('groups', 'assign_permissions', 'Change the permissions a group grants'),
  ('trips', 'read', 'View all trips'),
  ('trips', 'cancel', 'Cancel trips and their open bookings'),
  ('reservations', 'read', 'View bookings on trips'),
  ('dashboard', 'read', 'View operational dashboards'),
  ('audit', 'read', 'View the activity and audit trail');

-- Super Admins hold every permission.
INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g CROSS JOIN permissions p WHERE g.role = 'super_admin' AND g.is_system;

-- Admins hold everything except the audit trail.
INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g CROSS JOIN permissions p
WHERE g.role = 'admin' AND g.is_system AND p.resource <> 'audit';

INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON (p.resource, p.action) IN (
    ('dashboard', 'read'), ('trips', 'read'), ('trips', 'cancel'),
    ('reservations', 'read'), ('users', 'read')
  )
WHERE g.role = 'operator' AND g.is_system;

INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON (p.resource, p.action) IN (
    ('dashboard', 'read'), ('users', 'read'), ('users', 'manage_status'),
    ('trips', 'read'), ('reservations', 'read')
  )
WHERE g.role = 'support' AND g.is_system;

INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON (p.resource, p.action) IN (
    ('dashboard', 'read'), ('users', 'read'), ('trips', 'read')
  )
WHERE g.role = 'fleet_manager' AND g.is_system;

INSERT INTO group_permissions (group_id, permission_id)
SELECT g.id, p.id FROM groups g JOIN permissions p
  ON (p.resource, p.action) IN (
    ('dashboard', 'read'), ('trips', 'read'), ('reservations', 'read')
  )
WHERE g.role = 'finance' AND g.is_system;
