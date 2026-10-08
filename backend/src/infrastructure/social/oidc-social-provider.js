import { createRemoteJWKSet, jwtVerify } from 'jose';

import { unauthorized } from '../../domain/errors.js';

/**
 * Verifies an OpenID Connect ID token (a signed JWT) from a provider such as
 * Google or Apple. We validate the signature against the provider's published
 * JWKS and check the issuer and audience (our client id) ourselves — no client
 * secret is needed to verify an ID token, so this is safe to run server-side
 * from a token the mobile app obtained via its native sign-in SDK (with PKCE).
 */
export class OidcSocialProvider {
  constructor({ provider, issuer, jwksUri, audience }) {
    if (!provider || !issuer || !jwksUri || !audience) {
      throw new Error('OidcSocialProvider requires provider, issuer, jwksUri and audience.');
    }
    this.provider = provider;
    this.issuer = issuer.replace(/\/$/, '');
    // Allow one client id or several (e.g. iOS + Android + web for Google).
    this.audience = audience;
    this.jwks = createRemoteJWKSet(new URL(jwksUri));
  }

  async verify(token) {
    if (typeof token !== 'string' || token.length === 0) {
      throw unauthorized('A provider ID token is required.');
    }
    let payload;
    try {
      ({ payload } = await jwtVerify(token, this.jwks, {
        issuer: this.issuer,
        audience: this.audience,
      }));
    } catch {
      throw unauthorized('The provider ID token could not be verified.');
    }
    if (!payload.sub) throw unauthorized('The provider ID token has no subject.');
    return {
      provider: this.provider,
      providerUid: String(payload.sub),
      email: typeof payload.email === 'string' ? payload.email : null,
      // Apple/Google send email_verified as a boolean or the string "true".
      emailVerified: payload.email_verified === true || payload.email_verified === 'true',
      displayName:
        typeof payload.name === 'string'
          ? payload.name.slice(0, 120)
          : null,
    };
  }
}
