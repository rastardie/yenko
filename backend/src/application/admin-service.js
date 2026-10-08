import { randomInt } from 'node:crypto';

import { adminActionRequired, badRequest, conflict, forbidden, notFound } from '../domain/errors.js';
import { hasPermission, isSuperAdmin, isUuid } from '../domain/user.js';

const userStatuses = new Set(['active', 'suspended']);
const bookingStatuses = new Set(['requested', 'confirmed', 'cancelled', 'expired']);
const periods = new Set(['today', 'week', 'month', 'custom']);
const dayMs = 86_400_000;
const tripStatuses = new Set(['open', 'cancelled', 'completed']);
const temporaryPasswordAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

const generateTemporaryPassword = () =>
  Array.from({ length: 12 }, () => temporaryPasswordAlphabet[randomInt(temporaryPasswordAlphabet.length)]).join('');

const clampPage = ({ limit, offset }, max = 200) => ({
  limit: Math.min(Math.max(Number.isInteger(limit) ? limit : 50, 1), max),
  offset: Math.max(Number.isInteger(offset) ? offset : 0, 0),
});


const parseDay = (value, field) => {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw badRequest(`${field} must be a date like 2026-10-04.`);
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw badRequest(`${field} must be a valid date.`);
  }
  return date;
};

/**
 * Resolves a dashboard period to a half-open UTC range. UTC equals
 * Africa/Accra (GMT, no daylight saving). Weeks run Monday to Sunday.
 */
export const periodRange = (period = 'week', from, to, now = new Date()) => {
  if (!periods.has(period)) throw badRequest('period must be today, week, month or custom.');
  const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  if (period === 'today') return { from: today, to: new Date(today.getTime() + dayMs) };
  if (period === 'week') {
    const start = new Date(today.getTime() - ((today.getUTCDay() + 6) % 7) * dayMs);
    return { from: start, to: new Date(start.getTime() + 7 * dayMs) };
  }
  if (period === 'month') {
    return {
      from: new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1)),
      to: new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 1)),
    };
  }
  const start = parseDay(from, 'from');
  const end = new Date(parseDay(to, 'to').getTime() + dayMs);
  if (end <= start) throw badRequest('to must not be before from.');
  if (end.getTime() - start.getTime() > 366 * dayMs) throw badRequest('The date range cannot exceed one year.');
  return { from: start, to: end };
};

const optionalText = (value, { field, max }) => {
  if (value === undefined) return undefined;
  if (typeof value !== 'string' || value.trim().length > max) {
    throw badRequest(`${field} must be text of at most ${max} characters.`);
  }
  return value.trim();
};

/**
 * Administration use cases. Every method checks the caller's permissions
 * (evaluated from group membership on each request), then applies the
 * privilege-escalation rules below:
 *
 *  - Only a super admin may touch super admins or the Super Admins group, and
 *    that group's permissions are fixed to "everything".
 *  - Anyone else can only grant, revoke or assign what they themselves hold,
 *    so `groups:assign_members` can never be used to become more powerful.
 *  - The last active super admin can never be removed or suspended, and nobody
 *    can suspend their own account.
 */
export class AdminService {
  constructor({ adminRepository, userRepository, authService }) {
    this.admin = adminRepository;
    this.users = userRepository;
    this.auth = authService;
  }

  #require(actor, key) {
    if (!actor?.subject) throw forbidden('An authenticated actor is required.');
    if (!hasPermission(actor, key)) throw forbidden(`Your groups do not grant ${key}.`);
  }

  /** A write needs its permission and a fresh administrator re-authentication. */
  #requireWrite(actor, key) {
    this.#require(actor, key);
    if (!actor.adminActionVerified) throw adminActionRequired();
  }

  #audit(actor, action, metadata = {}) {
    return { actorId: actor.subject, action, metadata };
  }

  /** True when the actor holds every listed permission (or is a super admin). */
  #canGrant(actor, permissions) {
    return isSuperAdmin(actor) || permissions.every((key) => hasPermission(actor, key));
  }

  async #requireUser(id) {
    const user = typeof id === 'string' && id.length > 0 ? await this.admin.getUser(id) : null;
    if (!user) throw notFound('User not found.');
    return user;
  }

  async #requireGroup(id) {
    const group = isUuid(id) ? await this.admin.getGroup(id) : null;
    if (!group) throw notFound('Group not found.');
    return group;
  }

  #assertCanManageUser(actor, target) {
    if (target.roles.includes('super_admin') && !isSuperAdmin(actor)) {
      throw forbidden('Only a super admin can manage a super admin account.');
    }
  }

  #assertCanChangeMembership(actor, group) {
    if (group.role === 'super_admin' && group.isSystem && !isSuperAdmin(actor)) {
      throw forbidden('Only a super admin can change Super Admins membership.');
    }
    if (!this.#canGrant(actor, group.permissions)) {
      throw forbidden('You cannot manage a group that grants permissions you do not hold.');
    }
  }


  // ----- Summary, metrics and reports -----

  /** Counts for the admin home, limited to the sections the caller may see. */
  async summary(actor) {
    if (!actor?.subject || !Array.isArray(actor.permissions) || actor.permissions.length === 0) {
      throw forbidden('Your groups do not grant any admin permissions.');
    }
    const all = await this.admin.summary();
    return {
      ...(hasPermission(actor, 'users:read') ? { users: all.users } : {}),
      ...(hasPermission(actor, 'trips:read') ? { trips: all.trips } : {}),
      ...(hasPermission(actor, 'reservations:read') ? { bookings: all.bookings } : {}),
      ...(hasPermission(actor, 'groups:read') ? { groups: all.groups } : {}),
    };
  }

  async metrics(actor, { period, from, to }) {
    this.#require(actor, 'dashboard:read');
    const range = periodRange(period, from, to);
    return { period: period ?? 'week', ...(await this.admin.metrics(range)) };
  }

  async #bookings(actor, permission, filters) {
    this.#require(actor, permission);
    const status = filters.status || undefined;
    if (status !== undefined && !bookingStatuses.has(status)) {
      throw badRequest('status must be requested, confirmed, cancelled or expired.');
    }
    if (filters.womenOnly !== undefined && !['true', 'false'].includes(filters.womenOnly)) {
      throw badRequest('womenOnly must be true or false.');
    }
    const from = filters.from ? parseDay(filters.from, 'from') : undefined;
    const toDay = filters.to ? parseDay(filters.to, 'to') : undefined;
    if (from && toDay && toDay < from) throw badRequest('to must not be before from.');
    return this.admin.listBookings({
      from,
      to: toDay ? new Date(toDay.getTime() + dayMs) : undefined,
      status,
      womenOnly: filters.womenOnly === undefined ? undefined : filters.womenOnly === 'true',
      search: filters.search?.trim() || undefined,
      ...clampPage(filters, 1000),
    });
  }

  /** Operations > Bookings. */
  listBookings(actor, filters) {
    return this.#bookings(actor, 'reservations:read', filters);
  }

  /** Reports > Bookings (same data, separate permission, larger exports). */
  bookingReport(actor, filters) {
    return this.#bookings(actor, 'reports:read', filters);
  }

  async confirmBooking(actor, id) {
    this.#requireWrite(actor, 'reservations:manage');
    if (!isUuid(id)) throw notFound('Booking not found.');
    const result = await this.admin.confirmBooking(id, this.#audit(actor, 'admin.booking.confirmed'));
    if (result.reason === 'booking_not_found') throw notFound('Booking not found.');
    if (result.reason === 'booking_not_pending') throw conflict('Only a pending booking can be confirmed.');
    if (result.reason === 'trip_not_open') throw conflict('The trip is no longer open.');
    return { confirmed: true };
  }

  async cancelBooking(actor, id) {
    this.#requireWrite(actor, 'reservations:manage');
    if (!isUuid(id)) throw notFound('Booking not found.');
    const result = await this.admin.cancelBooking(id, this.#audit(actor, 'admin.booking.cancelled'));
    if (result.reason === 'booking_not_found') throw notFound('Booking not found.');
    if (result.reason === 'booking_not_cancellable') throw conflict('This booking can no longer be cancelled.');
    return { cancelled: true };
  }

  // ----- Approval and deletion -----

  async approveUser(actor, id) {
    this.#requireWrite(actor, 'users:approve');
    const target = await this.#requireUser(id);
    if (target.status !== 'pending') throw conflict('This account is not waiting for approval.');
    await this.admin.approveUser(id, this.#audit(actor, 'admin.user.approved'));
    return this.admin.getUser(id);
  }

  /** Denying removes the pending account (soft delete), keeping an audit record. */
  async denyUser(actor, id) {
    this.#requireWrite(actor, 'users:approve');
    const target = await this.#requireUser(id);
    if (target.status !== 'pending') throw conflict('This account is not waiting for approval.');
    await this.admin.deleteUser(id, this.#audit(actor, 'admin.user.denied'));
    return { denied: true };
  }

  async deleteUser(actor, id) {
    this.#requireWrite(actor, 'users:delete');
    const target = await this.#requireUser(id);
    if (target.status === 'deleted') throw notFound('User not found.');
    this.#assertCanManageUser(actor, target);
    if (id === actor.subject) throw conflict('You cannot delete your own account.');
    if (target.roles.includes('super_admin') && target.status === 'active'
        && (await this.admin.countActiveMembersOfRole('super_admin')) <= 1) {
      throw conflict('The last active super admin cannot be deleted.');
    }
    const { openTrips, openBookings } = await this.admin.openCommitments(id);
    if (openTrips > 0 || openBookings > 0) {
      throw conflict(
        `${target.displayName} still has ${openTrips} open trips and ${openBookings} open bookings. Cancel them first.`,
      );
    }
    await this.admin.deleteUser(id, this.#audit(actor, 'admin.user.deleted'));
    return { deleted: true };
  }

  async auditActions(actor) {
    this.#require(actor, 'audit:read');
    return this.admin.auditActions();
  }

  // ----- Dashboard -----

  async dashboard(actor) {
    this.#require(actor, 'dashboard:read');
    return this.admin.dashboard();
  }

  // ----- Users -----

  async listUsers(actor, { search, status, groupId, limit, offset }) {
    this.#require(actor, 'users:read');
    if (status !== undefined && status !== 'pending' && !userStatuses.has(status)) {
      throw badRequest('status must be active, suspended or pending.');
    }
    if (groupId !== undefined && !isUuid(groupId)) throw badRequest('groupId must be a valid id.');
    return this.admin.listUsers({
      search: search?.trim() || undefined,
      status,
      groupId,
      ...clampPage({ limit, offset }),
    });
  }

  async getUser(actor, id) {
    this.#require(actor, 'users:read');
    return this.#requireUser(id);
  }

  async createUser(actor, input) {
    this.#requireWrite(actor, 'users:create');
    const groupIds = Array.isArray(input?.groupIds) ? [...new Set(input.groupIds)] : [];
    const groups = [];
    for (const groupId of groupIds) {
      const group = await this.#requireGroup(groupId);
      this.#assertCanChangeMembership(actor, group);
      groups.push(group);
    }
    const generated = typeof input?.password !== 'string';
    const password = generated ? generateTemporaryPassword() : input.password;
    const account = await this.auth.createAccount({
      displayName: input?.displayName,
      username: input?.username,
      phone: input?.phone,
      password,
      quickPin: input?.quickPin,
      homeArea: input?.homeArea,
      role: 'passenger',
    });
    for (const group of groups) {
      await this.admin.addMember(group.id, account.id, this.#audit(actor, 'admin.group.member_added', { via: 'user_create' }));
    }
    await this.admin.recordUserAudit(account.id, this.#audit(actor, 'admin.user.created', {
      groups: groups.map((group) => group.name),
    }));
    const user = await this.admin.getUser(account.id);
    return generated ? { ...user, temporaryPassword: password } : user;
  }

  async updateUser(actor, id, input) {
    const changesProfile = input?.displayName !== undefined || input?.homeArea !== undefined;
    const changesStatus = input?.status !== undefined;
    if (!changesProfile && !changesStatus) {
      this.#requireWrite(actor, 'users:update');
      throw badRequest('Nothing to update.');
    }
    // Authorize before looking the account up, so callers without the
    // permission cannot probe which accounts exist.
    if (changesProfile) this.#requireWrite(actor, 'users:update');
    if (changesStatus) this.#requireWrite(actor, 'users:manage_status');
    const target = await this.#requireUser(id);
    this.#assertCanManageUser(actor, target);

    if (changesProfile) {
      const displayName = optionalText(input.displayName, { field: 'displayName', max: 120 });
      if (displayName !== undefined && displayName.length < 1) throw badRequest('displayName is required.');
      const homeArea = optionalText(input.homeArea, { field: 'homeArea', max: 120 });
      await this.admin.updateUser(id, { displayName, homeArea: homeArea === undefined ? undefined : homeArea || null },
        this.#audit(actor, 'admin.user.updated'));
    }
    if (changesStatus) {
      if (!userStatuses.has(input.status)) throw badRequest('status must be active or suspended.');
      if (input.status === 'suspended') {
        if (id === actor.subject) throw conflict('You cannot suspend your own account.');
        if (target.roles.includes('super_admin') && (await this.admin.countActiveMembersOfRole('super_admin')) <= 1) {
          throw conflict('The last active super admin cannot be suspended.');
        }
      }
      if (target.status !== input.status) {
        await this.admin.setUserStatus(id, input.status, this.#audit(actor, `admin.user.${input.status === 'active' ? 'restored' : 'suspended'}`));
      }
    }
    return this.admin.getUser(id);
  }

  async resetCredentials(actor, id, input) {
    this.#requireWrite(actor, 'users:reset_credentials');
    const target = await this.#requireUser(id);
    this.#assertCanManageUser(actor, target);
    const generated = input?.password === undefined;
    const password = generated ? generateTemporaryPassword() : input.password;
    await this.auth.setPassword(id, password);
    await this.admin.recordUserAudit(id, this.#audit(actor, 'admin.user.password_reset'));
    return generated ? { reset: true, temporaryPassword: password } : { reset: true };
  }

  // ----- Groups -----

  async listGroups(actor) {
    this.#require(actor, 'groups:read');
    return this.admin.listGroups();
  }

  async getGroup(actor, id) {
    this.#require(actor, 'groups:read');
    return this.#requireGroup(id);
  }

  async listPermissions(actor) {
    this.#require(actor, 'groups:read');
    return this.admin.listPermissions();
  }

  async #validatePermissionKeys(keys) {
    if (!Array.isArray(keys) || keys.some((key) => typeof key !== 'string')) {
      throw badRequest('permissions must be a list of permission keys.');
    }
    const known = new Set((await this.admin.listPermissions()).map((permission) => permission.key));
    const unknown = keys.filter((key) => !known.has(key));
    if (unknown.length) throw badRequest(`Unknown permissions: ${unknown.join(', ')}.`);
    return [...new Set(keys)].sort();
  }

  async createGroup(actor, input) {
    this.#requireWrite(actor, 'groups:create');
    const name = typeof input?.name === 'string' ? input.name.trim() : '';
    if (name.length < 2 || name.length > 80) throw badRequest('name must be between 2 and 80 characters.');
    const description = optionalText(input?.description, { field: 'description', max: 300 }) ?? '';
    const permissions = await this.#validatePermissionKeys(input?.permissions ?? []);
    if (!this.#canGrant(actor, permissions)) {
      throw forbidden('You can only create a group with permissions you hold yourself.');
    }
    if (await this.admin.findGroupByName(name)) throw conflict('A group with this name already exists.');
    return this.admin.createGroup({ name, description, permissions }, this.#audit(actor, 'admin.group.created'));
  }

  async updateGroup(actor, id, input) {
    this.#requireWrite(actor, 'groups:update');
    const group = await this.#requireGroup(id);
    this.#assertCanChangeMembership(actor, group);
    let name = optionalText(input?.name, { field: 'name', max: 80 });
    const description = optionalText(input?.description, { field: 'description', max: 300 });
    if (name !== undefined) {
      if (group.isSystem && name !== group.name) throw conflict('System groups cannot be renamed.');
      if (name.length < 2) throw badRequest('name must be between 2 and 80 characters.');
      const clash = await this.admin.findGroupByName(name);
      if (clash && clash.id !== id) throw conflict('A group with this name already exists.');
      if (name === group.name) name = undefined;
    }
    if (name === undefined && description === undefined) throw badRequest('Nothing to update.');
    await this.admin.updateGroup(id, { name, description }, this.#audit(actor, 'admin.group.updated'));
    return this.admin.getGroup(id);
  }

  async deleteGroup(actor, id) {
    this.#requireWrite(actor, 'groups:delete');
    const group = await this.#requireGroup(id);
    if (group.isSystem) throw conflict('System groups cannot be deleted.');
    this.#assertCanChangeMembership(actor, group);
    await this.admin.deleteGroup(id, this.#audit(actor, 'admin.group.deleted', { name: group.name }));
    return { deleted: true };
  }

  async setGroupPermissions(actor, id, input) {
    this.#requireWrite(actor, 'groups:assign_permissions');
    const group = await this.#requireGroup(id);
    if (group.role === 'super_admin' && group.isSystem) {
      throw conflict('Super Admins always hold every permission.');
    }
    const permissions = await this.#validatePermissionKeys(input?.permissions);
    const changed = [
      ...permissions.filter((key) => !group.permissions.includes(key)),
      ...group.permissions.filter((key) => !permissions.includes(key)),
    ];
    // Changing a permission requires holding it, so a group can never gain or
    // lose power that the acting admin does not possess.
    if (!this.#canGrant(actor, changed)) {
      throw forbidden('You can only grant or revoke permissions that you hold yourself.');
    }
    if (!isSuperAdmin(actor) && !this.#canGrant(actor, group.permissions)) {
      throw forbidden('You cannot modify a group that grants permissions you do not hold.');
    }
    await this.admin.setGroupPermissions(id, permissions, this.#audit(actor, 'admin.group.permissions_set', {
      added: permissions.filter((key) => !group.permissions.includes(key)),
      removed: group.permissions.filter((key) => !permissions.includes(key)),
    }));
    return this.admin.getGroup(id);
  }

  async addGroupMember(actor, groupId, input) {
    this.#requireWrite(actor, 'groups:assign_members');
    const group = await this.#requireGroup(groupId);
    const target = await this.#requireUser(input?.userId);
    this.#assertCanChangeMembership(actor, group);
    this.#assertCanManageUser(actor, target);
    await this.admin.addMember(groupId, target.id, this.#audit(actor, 'admin.group.member_added', { group: group.name }));
    return this.admin.getGroup(groupId);
  }

  async removeGroupMember(actor, groupId, userId) {
    this.#requireWrite(actor, 'groups:assign_members');
    const group = await this.#requireGroup(groupId);
    const target = await this.#requireUser(userId);
    this.#assertCanChangeMembership(actor, group);
    this.#assertCanManageUser(actor, target);
    if (!(await this.admin.isMember(groupId, userId))) throw notFound('That user is not in this group.');
    if (group.role === 'super_admin' && group.isSystem && target.status === 'active'
        && (await this.admin.countActiveMembersOfRole('super_admin')) <= 1) {
      throw conflict('The last active super admin cannot be removed.');
    }
    await this.admin.removeMember(groupId, userId, this.#audit(actor, 'admin.group.member_removed', { group: group.name }));
    return this.admin.getGroup(groupId);
  }

  // ----- Trips -----

  async listTrips(actor, { status, limit, offset }) {
    this.#require(actor, 'trips:read');
    if (status !== undefined && !tripStatuses.has(status)) {
      throw badRequest('status must be open, cancelled or completed.');
    }
    return this.admin.listTrips({ status, ...clampPage({ limit, offset }) });
  }

  async getTrip(actor, id) {
    this.#require(actor, 'trips:read');
    const trip = isUuid(id)
      ? await this.admin.getTrip(id, { includeReservations: hasPermission(actor, 'reservations:read') })
      : null;
    if (!trip) throw notFound('Trip not found.');
    return trip;
  }

  async cancelTrip(actor, id) {
    this.#requireWrite(actor, 'trips:cancel');
    if (!isUuid(id)) throw notFound('Trip not found.');
    const result = await this.admin.cancelTrip(id, this.#audit(actor, 'admin.trip.cancelled'));
    if (result.reason === 'trip_not_found') throw notFound('Trip not found.');
    if (result.reason === 'trip_not_open') throw conflict('Only an open trip can be cancelled.');
    return this.getTrip(actor, id);
  }

  // ----- Audit -----

  async listAudit(actor, { action, actorId, limit, offset }) {
    this.#require(actor, 'audit:read');
    return this.admin.listAudit({ action, actorId, ...clampPage({ limit, offset }) });
  }
}
