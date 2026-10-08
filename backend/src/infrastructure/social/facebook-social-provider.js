import { unauthorized } from '../../domain/errors.js';

/**
 * Verifies a Facebook user access token server-side via the Graph API: we check
 * the token belongs to our app with /debug_token (using an app access token of
 * `appId|appSecret`), then read the profile from /me. This is the classic
 * Facebook Login flow; the mobile app sends the access token it obtained.
 */
export class FacebookSocialProvider {
  provider = 'facebook';

  constructor({ appId, appSecret, graphBase = 'https://graph.facebook.com/v19.0', fetchImpl = fetch }) {
    if (!appId || !appSecret) throw new Error('FacebookSocialProvider requires appId and appSecret.');
    this.appId = appId;
    this.appSecret = appSecret;
    this.graphBase = graphBase.replace(/\/$/, '');
    this.fetch = fetchImpl;
  }

  async verify(token) {
    if (typeof token !== 'string' || token.length === 0) {
      throw unauthorized('A Facebook access token is required.');
    }
    const appToken = `${this.appId}|${this.appSecret}`;
    let debug;
    try {
      const response = await this.fetch(
        `${this.graphBase}/debug_token?input_token=${encodeURIComponent(token)}&access_token=${encodeURIComponent(appToken)}`,
      );
      debug = (await response.json())?.data;
    } catch {
      throw unauthorized('Facebook token verification failed.');
    }
    if (!debug?.is_valid || String(debug.app_id) !== String(this.appId)) {
      throw unauthorized('The Facebook token is not valid for this app.');
    }
    let profile;
    try {
      const response = await this.fetch(
        `${this.graphBase}/me?fields=id,name,email&access_token=${encodeURIComponent(token)}`,
      );
      profile = await response.json();
    } catch {
      throw unauthorized('Facebook profile lookup failed.');
    }
    if (!profile?.id) throw unauthorized('The Facebook token has no subject.');
    return {
      provider: this.provider,
      providerUid: String(profile.id),
      email: typeof profile.email === 'string' ? profile.email : null,
      // A Facebook account's email is already provider-verified when present.
      emailVerified: typeof profile.email === 'string',
      displayName: typeof profile.name === 'string' ? profile.name.slice(0, 120) : null,
    };
  }
}
