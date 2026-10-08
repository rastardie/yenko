import { unauthorized } from '../domain/errors.js';

/** Resolves the bearer token issued by AuthService into the actor shape trip-service expects. */
export class LocalAuthActorResolver {
  constructor({ authService }) {
    this.authService = authService;
  }

  async resolve(headers) {
    const authorization = headers.authorization;
    if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) {
      throw unauthorized('A bearer access token is required.');
    }
    return this.authService.verifyAccessToken(authorization.slice(7));
  }
}
