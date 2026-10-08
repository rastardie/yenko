import { badRequest, unauthorized } from '../domain/errors.js';

const roles = new Set(['driver', 'passenger']);

/**
 * Local-only adapter. These headers are not authentication and the application
 * rejects this adapter outside development/test environments.
 */
export class DevelopmentActorResolver {
  resolve(headers) {
    const subject = headers['x-yenko-actor-id'];
    const role = headers['x-yenko-role'];
    const displayName = headers['x-yenko-display-name'];
    if (!subject || !role) throw unauthorized('Local actor headers are required.');
    if (!/^[A-Za-z0-9_-]{3,80}$/.test(subject)) {
      throw badRequest('x-yenko-actor-id is invalid.');
    }
    if (!roles.has(role)) throw badRequest('x-yenko-role must be driver or passenger.');
    return {
      subject,
      role,
      displayName:
        typeof displayName === 'string' && displayName.trim()
          ? displayName.trim().slice(0, 60)
          : 'Local YɛnKɔ user',
    };
  }
}
