import { randomUUID } from 'node:crypto';

/** In-memory double for PostgresUserRepository, matching its exact interface, for unit tests. */
export class InMemoryUserRepository {
  #users = new Map();
  #groups = new Map([
    ['Riders', { id: randomUUID(), role: 'passenger', permissions: [] }],
    ['Drivers', { id: randomUUID(), role: 'driver', permissions: [] }],
    ['Admins', { id: randomUUID(), role: 'admin', permissions: ['users:read', 'groups:read'] }],
    ['Super Admins', { id: randomUUID(), role: 'super_admin', permissions: ['users:read', 'groups:read', 'audit:read'] }],
  ]);
  #groupMembers = new Set(); // `${groupId}:${userId}`
  #sessions = new Map();
  #otpCodes = new Map();
  #identities = new Map(); // `${provider}:${providerUid}`

  async findByPhone(phone) {
    return [...this.#users.values()].find((user) => user.phone === phone) ?? null;
  }

  async findByUsername(username) {
    return [...this.#users.values()].find((user) => user.username === username) ?? null;
  }

  async findByEmail(email) {
    return [...this.#users.values()].find((user) => user.email === email) ?? null;
  }

  async findIdentity(provider, providerUid) {
    return (
      [...this.#identities.values()].find(
        (identity) => identity.provider === provider && identity.provider_uid === providerUid,
      ) ?? null
    );
  }

  async createIdentity({ userId, provider, providerUid, email = null, emailVerified = false }) {
    const key = `${provider}:${providerUid}`;
    if (this.#identities.has(key)) return;
    this.#identities.set(key, {
      id: randomUUID(),
      user_id: userId,
      provider,
      provider_uid: providerUid,
      email,
      email_verified: emailVerified,
    });
  }

  async markEmailVerified(userId) {
    this.#users.get(userId).email_verified = true;
  }

  async findById(id) {
    return this.#users.get(id) ?? null;
  }

  async rolesForUser(userId) {
    const roles = [];
    for (const [name, group] of this.#groups) {
      if (this.#groupMembers.has(`${group.id}:${userId}`)) roles.push(group.role);
    }
    return roles;
  }

  async permissionsForUser(userId) {
    const keys = new Set();
    for (const group of this.#groups.values()) {
      if (this.#groupMembers.has(`${group.id}:${userId}`)) group.permissions.forEach((key) => keys.add(key));
    }
    return [...keys].sort();
  }

  async setPasswordHash(userId, passwordHash) {
    const user = this.#users.get(userId);
    user.password_hash = passwordHash;
    user.auth_version += 1;
  }

  async createUser({
    id = randomUUID(),
    displayName,
    phone,
    username,
    email,
    passwordHash,
    pinHash,
    homeArea,
    legalSurname = null,
    legalGivenNames = null,
    legalNameSource = 'self_attested',
    emailVerified = false,
    identity = null,
    roles = ['passenger'],
    status = 'active',
  }) {
    const user = {
      id, display_name: displayName, phone: phone ?? null, username: username ?? null,
      email: email ?? null, password_hash: passwordHash ?? null, pin_hash: pinHash ?? null,
      phone_verified: false, email_verified: emailVerified, must_change_pin: false,
      auth_version: 0, status, home_area: homeArea ?? null,
      legal_surname: legalSurname, legal_given_names: legalGivenNames,
      legal_name_source: legalNameSource, id_verified: false,
    };
    this.#users.set(id, user);
    const groupNames = { passenger: 'Riders', driver: 'Drivers', admin: 'Admins', super_admin: 'Super Admins' };
    const uniqueRoles = new Set(['passenger', ...roles]);
    for (const role of uniqueRoles) {
      const groupName = groupNames[role];
      if (!groupName) continue;
      this.#groupMembers.add(`${this.#groups.get(groupName).id}:${id}`);
    }
    if (identity) {
      await this.createIdentity({ userId: id, ...identity });
    }
    return user;
  }

  async setPinHash(userId, pinHash) {
    const user = this.#users.get(userId);
    user.pin_hash = pinHash;
    user.must_change_pin = false;
    user.auth_version += 1;
  }

  async markPhoneVerified(userId) {
    this.#users.get(userId).phone_verified = true;
  }

  async bumpAuthVersion(userId) {
    this.#users.get(userId).auth_version += 1;
  }

  async createSession({ userId, expiresAt }) {
    const id = randomUUID();
    this.#sessions.set(id, { id, user_id: userId, expires_at: expiresAt, revoked_at: null });
    return id;
  }

  async findSession(sessionId) {
    return this.#sessions.get(sessionId) ?? null;
  }

  async touchSession() {}

  async revokeSession(sessionId) {
    const session = this.#sessions.get(sessionId);
    if (session) session.revoked_at = new Date();
  }

  async createOtpCode({ userId, purpose, codeHash, expiresAt }) {
    const id = randomUUID();
    this.#otpCodes.set(id, { id, user_id: userId, purpose, code_hash: codeHash, expires_at: expiresAt, consumed_at: null, attempts: 0 });
    return id;
  }

  async findActiveOtpCode({ userId, purpose }) {
    return [...this.#otpCodes.values()]
      .filter((otp) => otp.user_id === userId && otp.purpose === purpose && !otp.consumed_at && otp.expires_at > new Date())
      .sort((left, right) => right.id.localeCompare(left.id))[0] ?? null;
  }

  async incrementOtpAttempts(otpId) {
    this.#otpCodes.get(otpId).attempts += 1;
  }

  async consumeOtpCode(otpId) {
    this.#otpCodes.get(otpId).consumed_at = new Date();
  }

  /** Test helper only: adds userId to the named role group. */
  async addToGroup(userId, groupName) {
    this.#groupMembers.add(`${this.#groups.get(groupName).id}:${userId}`);
  }
}
