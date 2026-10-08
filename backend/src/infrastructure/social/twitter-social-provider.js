import { unauthorized } from '../../domain/errors.js';

/**
 * Verifies an X (Twitter) OAuth 2.0 user-context access token by calling the
 * v2 /users/me endpoint with it. X does not return an email through the public
 * v2 API, so email stays null and the mandatory username plus the self-attested
 * legal name carry identity for X signups.
 */
export class TwitterSocialProvider {
  provider = 'twitter';

  constructor({ apiBase = 'https://api.twitter.com/2', fetchImpl = fetch } = {}) {
    this.apiBase = apiBase.replace(/\/$/, '');
    this.fetch = fetchImpl;
  }

  async verify(token) {
    if (typeof token !== 'string' || token.length === 0) {
      throw unauthorized('An X access token is required.');
    }
    let user;
    try {
      const response = await this.fetch(`${this.apiBase}/users/me?user.fields=name,username`, {
        headers: { authorization: `Bearer ${token}` },
      });
      user = (await response.json())?.data;
    } catch {
      throw unauthorized('X token verification failed.');
    }
    if (!user?.id) throw unauthorized('The X token could not be verified.');
    return {
      provider: this.provider,
      providerUid: String(user.id),
      email: null,
      emailVerified: false,
      displayName: typeof user.name === 'string' ? user.name.slice(0, 120) : null,
    };
  }
}
