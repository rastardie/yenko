import { randomInt } from 'node:crypto';

import bcrypt from 'bcryptjs';
import { SignJWT, jwtVerify } from 'jose';

import {
  adminActionRequired,
  badRequest,
  conflict,
  forbidden,
  tooManyAttempts,
  unauthorized,
} from '../domain/errors.js';
import { isValidPhone, isValidPin, isValidUsername, isValidEmail, isValidLegalNamePart, socialProviders, primaryRole } from '../domain/user.js';

const bcryptCost = 10;
const sessionTtlHours = 12;
const otpTtlMinutes = 5;
const otpMaxAttempts = 5;
const adminActionTtlMinutes = 5;
const adminActionMaxFailures = 5;
const adminActionLockMinutes = 10;
// Valid-format bcrypt hash of a random value; used only to equalize timing.
const dummyHash = '$2a$10$wBuyP5b/KzgleqrsPJA0I.VwGPk1ELqxwbC0GZ5HINbaKAj4JpFZC';

const normalizePhone = (phone) => (typeof phone === 'string' ? phone.trim() : phone);
const normalizeUsername = (username) =>
  typeof username === 'string' ? username.trim().toLowerCase() : username;
const normalizeEmail = (email) => (typeof email === 'string' ? email.trim().toLowerCase() : email);

/**
 * Phone/username + PIN authentication with JWT sessions, mirroring Onboard's
 * proven model (bcrypt-hashed PIN, per-session revocation, auth_version bump
 * to invalidate all tokens on a credential/PIN change) adapted to a single
 * plain-Node service with no framework dependency.
 */
export class AuthService {
  /**
   * @param signupApproval Who must be approved by an administrator before they
   *   can sign in: 'none' (default), 'drivers' or 'all'. Accounts created by an
   *   administrator are always active.
   */
  constructor({ userRepository, jwtSecret, smsSender = null, mailSender = null, socialProviders: socialRegistry = null, signupApproval = 'none' }) {
    if (!jwtSecret) throw new Error('jwtSecret is required.');
    if (!['none', 'drivers', 'all'].includes(signupApproval)) {
      throw new Error('signupApproval must be none, drivers or all.');
    }
    this.users = userRepository;
    this.secret = new TextEncoder().encode(jwtSecret);
    this.smsSender = smsSender;
    this.mailSender = mailSender;
    this.social = socialRegistry;
    this.signupApproval = signupApproval;
    this.adminActionFailures = new Map();
  }

  async signup(input) {
    const needsApproval =
      this.signupApproval === 'all' || (this.signupApproval === 'drivers' && input?.role === 'driver');
    const user = await this.createAccount({ ...input, status: needsApproval ? 'pending' : 'active' });
    if (needsApproval) {
      return {
        pending: true,
        message: 'Your account was created and is waiting for approval. You can sign in once it is approved.',
      };
    }
    return this.#issueSession(user);
  }

  /**
   * Validates and creates an account without starting a session. Used by
   * self-service signup and by administrators creating users.
   */
  async createAccount({
    id,
    displayName,
    phone,
    username,
    email,
    password,
    quickPin,
    pin,
    role,
    homeArea,
    legalSurname = null,
    legalGivenNames = null,
    legalNameSource = 'self_attested',
    emailVerified = false,
    identity = null,
    status = 'active',
  }) {
    const trimmedName = typeof displayName === 'string' ? displayName.trim() : '';
    if (trimmedName.length < 1 || trimmedName.length > 120) {
      throw badRequest('displayName must be between 1 and 120 characters.');
    }
    const normalizedPhone = normalizePhone(phone);
    const normalizedUsername = normalizeUsername(username);
    const normalizedEmail = normalizeEmail(email);
    if (normalizedPhone != null && !isValidPhone(normalizedPhone)) {
      throw badRequest('phone must be in E.164 format, e.g. +233200000000.');
    }
    if (normalizedUsername != null && !isValidUsername(normalizedUsername)) {
      throw badRequest('username must be 3-32 lowercase letters, numbers, or ._- characters.');
    }
    if (normalizedEmail != null && !isValidEmail(normalizedEmail)) {
      throw badRequest('email must be a valid email address.');
    }
    if (!normalizedPhone && !normalizedUsername && !normalizedEmail) {
      throw badRequest('A phone number, username or email is required.');
    }

    // Legal name parts, when supplied, are validated and trimmed. They are kept
    // separate from displayName and (for now) are self-attested.
    const surname = legalSurname == null ? null : String(legalSurname).trim();
    const givenNames = legalGivenNames == null ? null : String(legalGivenNames).trim();
    if (surname != null && !isValidLegalNamePart(surname)) {
      throw badRequest('legalSurname must be a valid name (letters, spaces, hyphen or apostrophe).');
    }
    if (givenNames != null && !isValidLegalNamePart(givenNames)) {
      throw badRequest('legalGivenNames must be a valid name (letters, spaces, hyphen or apostrophe).');
    }

    // A password/PIN is required unless the account authenticates through a
    // linked social identity instead.
    const primaryPassword = typeof password === 'string' ? password : pin;
    const minimumPasswordLength = typeof password === 'string' ? 8 : 4;
    let passwordHash = null;
    if (primaryPassword != null || !identity) {
      if (typeof primaryPassword !== 'string' || primaryPassword.length < minimumPasswordLength || primaryPassword.length > 128) {
        throw badRequest(`password must be between ${minimumPasswordLength} and 128 characters.`);
      }
      passwordHash = await bcrypt.hash(primaryPassword, bcryptCost);
    }
    if (quickPin != null && !isValidPin(quickPin)) {
      throw badRequest('quickPin must be between 4 and 20 characters.');
    }

    const requestedRole = role === 'driver' ? 'driver' : 'passenger';
    const trimmedHomeArea = typeof homeArea === 'string' ? homeArea.trim() : '';
    if (trimmedHomeArea.length > 120) {
      throw badRequest('homeArea must be at most 120 characters.');
    }

    if (normalizedPhone && (await this.users.findByPhone(normalizedPhone))) {
      throw conflict('An account with this phone number already exists.');
    }
    if (normalizedUsername && (await this.users.findByUsername(normalizedUsername))) {
      throw conflict('An account with this username already exists.');
    }
    if (normalizedEmail && (await this.users.findByEmail(normalizedEmail))) {
      throw conflict('An account with this email already exists.');
    }

    const quickPinHash = quickPin == null ? null : await bcrypt.hash(quickPin, bcryptCost);
    const user = await this.users.createUser({
      ...(id ? { id } : {}),
      displayName: trimmedName,
      phone: normalizedPhone ?? null,
      username: normalizedUsername ?? null,
      email: normalizedEmail ?? null,
      passwordHash,
      pinHash: quickPinHash,
      homeArea: trimmedHomeArea || null,
      legalSurname: surname,
      legalGivenNames: givenNames,
      legalNameSource,
      emailVerified,
      identity,
      roles: [requestedRole],
      status,
    });
    return user;
  }

  /**
   * Self-service signup with an email address and password. The legal name is
   * mandatory and (for now) self-attested. A password identity is linked and an
   * email verification code is issued; the account can still sign in while the
   * email is unverified unless an approval policy applies.
   */
  async emailSignup({ email, password, username, displayName, legalSurname, legalGivenNames, role, homeArea }) {
    const normalizedEmail = normalizeEmail(email);
    if (!isValidEmail(normalizedEmail)) throw badRequest('A valid email address is required.');
    const { surname, givenNames } = this.#requireLegalName(legalSurname, legalGivenNames);
    const name =
      (typeof displayName === 'string' && displayName.trim()) || `${givenNames} ${surname}`;
    const needsApproval =
      this.signupApproval === 'all' || (this.signupApproval === 'drivers' && role === 'driver');
    const user = await this.createAccount({
      displayName: name,
      email: normalizedEmail,
      username,
      password,
      role,
      homeArea,
      legalSurname: surname,
      legalGivenNames: givenNames,
      identity: { provider: 'password', providerUid: normalizedEmail, email: normalizedEmail, emailVerified: false },
      status: needsApproval ? 'pending' : 'active',
    });
    const verification = await this.#issueOtp({ userId: user.id, purpose: 'email_verification' });
    if (needsApproval) {
      return {
        pending: true,
        message: 'Your account was created and is waiting for approval. Verify your email in the meantime.',
        ...verification,
      };
    }
    const session = await this.#issueSession(user);
    return { ...session, emailVerificationRequired: true, ...verification };
  }

  /**
   * Signs in or signs up through a social provider. The provider token is
   * verified server-side. A known identity signs in; a verified email matching
   * an existing account links to it; otherwise a new account is created, which
   * requires a username and a (self-attested) legal name.
   */
  async socialAuth({ provider, token, username, displayName, legalSurname, legalGivenNames, role, homeArea }) {
    if (!socialProviders.includes(provider)) throw badRequest('Unsupported social provider.');
    if (!this.social) throw badRequest('Social sign-in is not enabled.');
    const profile = await this.social.get(provider).verify(token);

    const existing = await this.users.findIdentity(provider, profile.providerUid);
    if (existing) {
      return this.#issueSocialSession(await this.users.findById(existing.user_id));
    }

    const providerEmail = profile.email ? normalizeEmail(profile.email) : null;
    if (providerEmail && profile.emailVerified) {
      const linked = await this.users.findByEmail(providerEmail);
      if (linked) {
        await this.users.createIdentity({
          userId: linked.id,
          provider,
          providerUid: profile.providerUid,
          email: providerEmail,
          emailVerified: true,
        });
        return this.#issueSocialSession(linked);
      }
    }

    // First-time social signup: a username is mandatory, and so is a legal name.
    const normalizedUsername = normalizeUsername(username);
    if (!isValidUsername(normalizedUsername)) {
      throw badRequest(`A username (3-32 lowercase letters, numbers or ._-) is required to sign up with ${provider}.`);
    }
    const { surname, givenNames } = this.#requireLegalName(legalSurname, legalGivenNames);
    const name =
      (typeof displayName === 'string' && displayName.trim()) ||
      (typeof profile.displayName === 'string' && profile.displayName.trim()) ||
      `${givenNames} ${surname}`;
    const needsApproval =
      this.signupApproval === 'all' || (this.signupApproval === 'drivers' && role === 'driver');
    const user = await this.createAccount({
      displayName: name,
      username: normalizedUsername,
      email: providerEmail,
      emailVerified: Boolean(providerEmail && profile.emailVerified),
      role,
      homeArea,
      legalSurname: surname,
      legalGivenNames: givenNames,
      identity: {
        provider,
        providerUid: profile.providerUid,
        email: providerEmail,
        emailVerified: Boolean(profile.emailVerified),
      },
      status: needsApproval ? 'pending' : 'active',
    });
    if (needsApproval) {
      return { pending: true, message: 'Your account was created and is waiting for approval.' };
    }
    return this.#issueSession(user);
  }

  /** Issues a session for a social login, applying the same status rules as login. */
  async #issueSocialSession(user) {
    if (!user) throw unauthorized('Account not found.');
    if (user.status === 'suspended') throw forbidden('This account has been suspended.');
    if (user.status === 'pending') {
      return { pending: true, message: 'This account is waiting for approval.' };
    }
    return this.#issueSession(user);
  }

  /** Requires and normalizes both legal name parts (self-attested). */
  #requireLegalName(legalSurname, legalGivenNames) {
    const surname = typeof legalSurname === 'string' ? legalSurname.trim() : '';
    const givenNames = typeof legalGivenNames === 'string' ? legalGivenNames.trim() : '';
    if (!isValidLegalNamePart(surname) || !isValidLegalNamePart(givenNames)) {
      throw badRequest('Your full legal name (surname and given names, as on your national ID) is required.');
    }
    return { surname, givenNames };
  }

  async requestEmailVerification(userId) {
    const user = await this.users.findById(userId);
    if (!user) throw unauthorized('Account not found.');
    if (!user.email) throw badRequest('This account has no email to verify.');
    if (user.email_verified) return { alreadyVerified: true };
    return this.#issueOtp({ userId, purpose: 'email_verification' });
  }

  async confirmEmailVerification({ userId, code }) {
    await this.#verifyOtp({ userId, purpose: 'email_verification', code });
    await this.users.markEmailVerified(userId);
  }

  /** Hashes and stores a new primary password, revoking existing sessions. */
  async setPassword(userId, password) {
    if (typeof password !== 'string' || password.length < 8 || password.length > 128) {
      throw badRequest('password must be between 8 and 128 characters.');
    }
    await this.users.setPasswordHash(userId, await bcrypt.hash(password, bcryptCost));
  }

  async login({ identity, password, pin }) {
    if (typeof identity !== 'string' || identity.trim().length === 0) {
      throw badRequest('identity is required.');
    }
    const credential = typeof password === 'string' ? password : pin;
    if (typeof credential !== 'string' || credential.length === 0) {
      throw badRequest('password is required.');
    }

    const trimmed = identity.trim();
    const user = isValidPhone(trimmed)
      ? await this.users.findByPhone(trimmed)
      : isValidEmail(trimmed)
        ? await this.users.findByEmail(normalizeEmail(trimmed))
        : await this.users.findByUsername(normalizeUsername(trimmed));

    // Always run the comparison, even for an unknown account, so timing does
    // not reveal whether the account exists.
    const credentialOk = await this.#credentialMatches(user, credential);
    if (!user || !credentialOk) throw unauthorized('Incorrect username or password.');
    if (user.status === 'suspended') throw forbidden('This account has been suspended.');
    if (user.status === 'pending') throw forbidden('This account is waiting for approval.');
    if (user.status !== 'active') throw unauthorized('Incorrect username or password.');

    return this.#issueSession(user);
  }

  /**
   * Both comparisons always run (against a dummy hash when the account or the
   * credential is absent) so timing does not reveal whether an account exists
   * or which credentials it has set. The credential may be either the account
   * password or the quick PIN.
   */
  async #credentialMatches(user, credential) {
    const [passwordMatches, pinMatches] = await Promise.all([
      bcrypt.compare(credential, user?.password_hash ?? dummyHash),
      bcrypt.compare(credential, user?.pin_hash ?? dummyHash),
    ]);
    return Boolean(user) && (passwordMatches || pinMatches);
  }

  /**
   * Re-authentication for sensitive administrator actions (Onboard's
   * "admin action token"): the signed-in admin proves they still hold the
   * password or PIN and receives a short-lived token that admin write requests
   * must carry. Repeated failures are throttled per account.
   */
  async issueAdminActionToken({ userId, credential }) {
    if (typeof credential !== 'string' || credential.length === 0) {
      throw badRequest('Enter your password or PIN.');
    }
    const now = Date.now();
    const record = this.adminActionFailures.get(userId);
    if (record && record.lockedUntil > now) throw tooManyAttempts();
    const user = await this.users.findById(userId);
    const credentialOk = await this.#credentialMatches(user, credential);
    if (!user || user.status !== 'active' || !credentialOk) {
      const failures = (record && record.lockedUntil === 0 ? record.failures : 0) + 1;
      const locked = failures >= adminActionMaxFailures;
      this.adminActionFailures.set(userId, {
        failures: locked ? 0 : failures,
        lockedUntil: locked ? now + adminActionLockMinutes * 60_000 : 0,
      });
      throw unauthorized('Incorrect password or PIN.');
    }
    this.adminActionFailures.delete(userId);
    const expiresAt = new Date(now + adminActionTtlMinutes * 60_000);
    const token = await new SignJWT({ purpose: 'admin_action', authVersion: user.auth_version })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(user.id)
      .setIssuedAt()
      .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
      .sign(this.secret);
    return { token, expiresAt: expiresAt.toISOString() };
  }

  /** True only for an unexpired admin-action token issued to this same account. */
  async verifyAdminActionToken(token, userId) {
    if (typeof token !== 'string' || token.length === 0) return false;
    try {
      const { payload } = await jwtVerify(token, this.secret);
      if (payload.purpose !== 'admin_action' || payload.sub !== userId) return false;
      const user = await this.users.findById(userId);
      return Boolean(user) && user.status === 'active' && payload.authVersion === user.auth_version;
    } catch {
      return false;
    }
  }

  async requestPhoneVerification(userId) {
    const user = await this.users.findById(userId);
    if (!user) throw unauthorized('Account not found.');
    if (!user.phone) throw badRequest('This account has no phone number to verify.');
    return this.#issueOtp({ userId, purpose: 'phone_verification' });
  }

  async confirmPhoneVerification({ userId, code }) {
    await this.#verifyOtp({ userId, purpose: 'phone_verification', code });
    await this.users.markPhoneVerified(userId);
  }

  async requestPinReset(identity) {
    const trimmed = typeof identity === 'string' ? identity.trim() : '';
    const user = isValidPhone(trimmed)
      ? await this.users.findByPhone(trimmed)
      : await this.users.findByUsername(normalizeUsername(trimmed));
    // Deliberately non-revealing: the caller cannot tell whether the account
    // exists. An OTP is only actually issued/sent when it does and has a phone.
    if (user?.phone) {
      await this.#issueOtp({ userId: user.id, purpose: 'pin_reset' });
    }
    return { message: 'If an account exists, a reset code has been sent.' };
  }

  async confirmPinReset({ identity, code, newPin }) {
    if (!isValidPin(newPin)) throw badRequest('newPin must be between 4 and 20 characters.');
    const trimmed = typeof identity === 'string' ? identity.trim() : '';
    const user = isValidPhone(trimmed)
      ? await this.users.findByPhone(trimmed)
      : await this.users.findByUsername(normalizeUsername(trimmed));
    if (!user) throw unauthorized('Invalid identity or code.');
    await this.#verifyOtp({ userId: user.id, purpose: 'pin_reset', code });
    const pinHash = await bcrypt.hash(newPin, bcryptCost);
    await this.users.setPinHash(user.id, pinHash);
  }

  async logout(sessionId) {
    if (sessionId) await this.users.revokeSession(sessionId);
  }

  /** Verifies a bearer access token and returns the actor shape the trip service expects. */
  async verifyAccessToken(token) {
    let payload;
    try {
      ({ payload } = await jwtVerify(token, this.secret));
    } catch {
      throw unauthorized('The access token is invalid or has expired.');
    }
    const user = await this.users.findById(payload.sub);
    if (!user || user.status !== 'active') throw unauthorized('This account is no longer active.');
    if (payload.authVersion !== user.auth_version) {
      throw unauthorized('This session is no longer valid. Please sign in again.');
    }
    const session = await this.users.findSession(payload.sid);
    if (!session || session.revoked_at || new Date(session.expires_at) < new Date()) {
      throw unauthorized('This session has expired. Please sign in again.');
    }
    await this.users.touchSession(session.id);

    const roles = await this.users.rolesForUser(user.id);
    const permissions = await this.users.permissionsForUser(user.id);
    return {
      subject: user.id,
      sessionId: session.id,
      role: primaryRole(roles),
      roles,
      permissions,
      displayName: user.display_name,
      phoneVerified: user.phone_verified,
    };
  }

  async #issueSession(user) {
    const expiresAt = new Date(Date.now() + sessionTtlHours * 60 * 60 * 1000);
    const sessionId = await this.users.createSession({ userId: user.id, expiresAt });
    const roles = await this.users.rolesForUser(user.id);
    const permissions = await this.users.permissionsForUser(user.id);
    const accessToken = await new SignJWT({
      authVersion: user.auth_version,
      sid: sessionId,
    })
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(user.id)
      .setIssuedAt()
      .setExpirationTime(`${sessionTtlHours}h`)
      .sign(this.secret);

    return {
      accessToken,
      mustChangePin: user.must_change_pin,
      user: {
        id: user.id,
        displayName: user.display_name,
        phone: user.phone,
        username: user.username,
        email: user.email,
        phoneVerified: user.phone_verified,
        emailVerified: user.email_verified,
        role: primaryRole(roles),
        roles,
        permissions,
      },
    };
  }

  async #issueOtp({ userId, purpose }) {
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    const codeHash = await bcrypt.hash(code, bcryptCost);
    const expiresAt = new Date(Date.now() + otpTtlMinutes * 60 * 1000);
    await this.users.createOtpCode({ userId, purpose, codeHash, expiresAt });
    const user = await this.users.findById(userId);
    if (purpose === 'email_verification') {
      if (this.mailSender && user.email) {
        await this.mailSender.send({
          to: user.email,
          subject: 'Your YɛnKɔ verification code',
          body: `Your YɛnKɔ verification code is ${code}. It expires in ${otpTtlMinutes} minutes.`,
        });
        return {};
      }
      return { devCode: code };
    }
    if (this.smsSender) {
      await this.smsSender.send({ to: user.phone, body: `Your YɛnKɔ code is ${code}.` });
      return {};
    }
    // No SMS provider configured (local/dev): return the code directly so the
    // flow can be exercised without a real provider. Never do this in
    // production — require smsSender to be configured there instead.
    return { devCode: code };
  }

  async #verifyOtp({ userId, purpose, code }) {
    if (typeof code !== 'string' || !/^\d{6}$/.test(code)) throw badRequest('code must be 6 digits.');
    const otp = await this.users.findActiveOtpCode({ userId, purpose });
    if (!otp) throw badRequest('No active code found. Request a new one.');
    if (otp.attempts >= otpMaxAttempts) throw forbidden('Too many attempts. Request a new code.');
    const matches = await bcrypt.compare(code, otp.code_hash);
    if (!matches) {
      await this.users.incrementOtpAttempts(otp.id);
      throw badRequest('Incorrect code.');
    }
    await this.users.consumeOtpCode(otp.id);
  }
}
