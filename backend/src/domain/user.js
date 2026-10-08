/**
 * A user may belong to several groups, but the application acts on a single
 * primary role. Staff roles outrank driver, which outranks passenger.
 */
const rolePriority = [
  'super_admin',
  'admin',
  'operator',
  'support',
  'finance',
  'fleet_manager',
  'driver',
  'passenger',
];

/** Roles that may enter the admin console (also gated per permission). */
export const staffRoles = new Set([
  'super_admin',
  'admin',
  'operator',
  'support',
  'finance',
  'fleet_manager',
]);

export const primaryRole = (roles) => {
  for (const candidate of rolePriority) {
    if (roles.includes(candidate)) return candidate;
  }
  return 'passenger';
};

export const isValidPhone = (value) => typeof value === 'string' && /^\+\d{7,15}$/.test(value);

export const isValidUsername = (value) =>
  typeof value === 'string' && /^[a-z0-9_.-]{3,32}$/.test(value);

export const isValidPin = (value) => typeof value === 'string' && value.length >= 4 && value.length <= 20;

// Deliberately permissive, pragmatic email check: a single @, no spaces, a dot
// in the domain. Real deliverability is proven by the verification code, not by
// the regex, so we avoid the false negatives of an over-strict pattern.
export const isValidEmail = (value) =>
  typeof value === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254;

/**
 * A legal name part as written on a Ghana Card: letters (including accented),
 * spaces, hyphens, apostrophes and periods. No digits. 1-80 characters. This
 * covers Ghanaian names without being so strict that it rejects valid ones.
 */
export const isValidLegalNamePart = (value) =>
  typeof value === 'string' &&
  value.trim().length >= 1 &&
  value.trim().length <= 80 &&
  /^[\p{L}][\p{L} .'-]*$/u.test(value.trim());

/** Supported social providers (email/password is handled separately). */
export const socialProviders = Object.freeze(['google', 'apple', 'facebook', 'twitter']);

/** Ghanaian mobile money networks a driver may register a payout number for. */
export const momoNetworks = Object.freeze(['mtn', 'telecel', 'airteltigo']);

export const isValidMomoNumber = (value) =>
  typeof value === 'string' && /^\+?[0-9]{9,15}$/.test(value);


/** Permission keys are `resource:action`, e.g. `users:read`. */
export const permissionKey = (resource, action) => `${resource}:${action}`;

export const hasPermission = (actor, key) =>
  Array.isArray(actor?.permissions) && actor.permissions.includes(key);

export const isSuperAdmin = (actor) =>
  Array.isArray(actor?.roles) && actor.roles.includes('super_admin');

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUuid = (value) => typeof value === 'string' && uuidPattern.test(value);
