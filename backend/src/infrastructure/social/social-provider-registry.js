import { badRequest } from '../../domain/errors.js';
import { OidcSocialProvider } from './oidc-social-provider.js';
import { FacebookSocialProvider } from './facebook-social-provider.js';
import { TwitterSocialProvider } from './twitter-social-provider.js';

/**
 * Holds the social providers that are configured for this deployment. Each
 * provider is optional and only enabled when its credentials are supplied, so
 * the feature is dark until an operator turns it on. `get` throws a clear error
 * for a provider that is not configured.
 */
export class SocialProviderRegistry {
  #providers = new Map();

  constructor(providers = []) {
    for (const provider of providers) {
      if (provider) this.#providers.set(provider.provider, provider);
    }
  }

  has(name) {
    return this.#providers.has(name);
  }

  enabled() {
    return [...this.#providers.keys()];
  }

  get(name) {
    const provider = this.#providers.get(name);
    if (!provider) throw badRequest(`Social sign-in with "${name}" is not enabled.`);
    return provider;
  }

  /**
   * Builds the registry from environment configuration. Google and Apple use
   * OIDC ID-token verification; Facebook and X use their token-introspection
   * APIs. Anything without credentials is simply left disabled.
   */
  static fromEnv(env = process.env) {
    const providers = [];
    if (env.GOOGLE_CLIENT_ID) {
      providers.push(
        new OidcSocialProvider({
          provider: 'google',
          issuer: 'https://accounts.google.com',
          jwksUri: 'https://www.googleapis.com/oauth2/v3/certs',
          audience: env.GOOGLE_CLIENT_ID.split(',').map((value) => value.trim()),
        }),
      );
    }
    if (env.APPLE_CLIENT_ID) {
      providers.push(
        new OidcSocialProvider({
          provider: 'apple',
          issuer: 'https://appleid.apple.com',
          jwksUri: 'https://appleid.apple.com/auth/keys',
          audience: env.APPLE_CLIENT_ID.split(',').map((value) => value.trim()),
        }),
      );
    }
    if (env.FACEBOOK_APP_ID && env.FACEBOOK_APP_SECRET) {
      providers.push(
        new FacebookSocialProvider({
          appId: env.FACEBOOK_APP_ID,
          appSecret: env.FACEBOOK_APP_SECRET,
        }),
      );
    }
    if (env.TWITTER_ENABLED === 'true') {
      providers.push(new TwitterSocialProvider());
    }
    return new SocialProviderRegistry(providers);
  }
}
