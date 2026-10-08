import { createRemoteJWKSet, jwtVerify } from 'jose';

import { unauthorized } from '../domain/errors.js';

const supportedRoles = new Set(['driver', 'passenger']);

/** Verifies OIDC access tokens; provider-specific configuration stays in env. */
export class OidcActorResolver {
  constructor({ issuer, audience, rolesClaim = 'roles' }) {
    if (!issuer || !audience) throw new Error('OIDC_ISSUER and OIDC_AUDIENCE are required.');
    this.issuer = issuer.replace(/\/$/, '');
    this.audience = audience;
    this.rolesClaim = rolesClaim;
    this.jwks = createRemoteJWKSet(new URL(`${this.issuer}/.well-known/jwks.json`));
  }

  async resolve(headers) {
    const authorization = headers.authorization;
    if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) {
      throw unauthorized('A bearer access token is required.');
    }
    try {
      const { payload } = await jwtVerify(authorization.slice(7), this.jwks, {
        issuer: this.issuer,
        audience: this.audience,
      });
      const roles = Array.isArray(payload[this.rolesClaim])
        ? payload[this.rolesClaim].map(String)
        : [payload.role ?? payload[this.rolesClaim]].filter(Boolean).map(String);
      const role = roles.find((candidate) => supportedRoles.has(candidate));
      if (!payload.sub || !role) throw unauthorized('The access token has no supported YɛnKɔ role.');
      return {
        subject: String(payload.sub),
        role,
        displayName: String(payload.name ?? payload.preferred_username ?? 'YɛnKɔ user').slice(0, 60),
      };
    } catch (error) {
      if (error?.code === 'unauthorized') throw error;
      throw unauthorized('The access token could not be verified.');
    }
  }
}
