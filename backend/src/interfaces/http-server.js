import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';

import { AppError, badRequest, notFound } from '../domain/errors.js';
import { handleAdminRequest } from './admin-routes.js';

const maxBodyBytes = 64 * 1024;

const sendJson = (response, status, body, requestId) => {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'x-request-id': requestId,
  });
  response.end(JSON.stringify(body));
};

const readJson = async (request) => {
  const contentType = request.headers['content-type'] ?? '';
  if (!contentType.toLowerCase().startsWith('application/json')) {
    throw badRequest('Content-Type must be application/json.');
  }
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maxBodyBytes) throw badRequest('Request body exceeds 64 KiB.');
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw badRequest('Request body must be valid JSON.');
  }
};

const parseWomenOnly = (url) => {
  const value = url.searchParams.get('womenOnly');
  if (value === null) return false;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw badRequest('womenOnly must be true or false.');
};

export function createHttpServer({ tripService, actorResolver, authService, adminService }) {
  return createServer(async (request, response) => {
    const requestId = randomUUID();
    try {
      const url = new URL(request.url ?? '/', 'http://localhost');
      if (request.method === 'GET' && url.pathname === '/health/live') {
        return sendJson(response, 200, { status: 'ok' }, requestId);
      }
      if (request.method === 'GET' && url.pathname === '/health/ready') {
        return sendJson(response, 200, { status: 'ready' }, requestId);
      }
      if (authService) {
        if (request.method === 'POST' && url.pathname === '/v1/auth/signup') {
          const result = await authService.signup(await readJson(request));
          return sendJson(response, result.pending ? 202 : 201, { data: result }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/email/signup') {
          const result = await authService.emailSignup(await readJson(request));
          return sendJson(response, result.pending ? 202 : 201, { data: result }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/social') {
          const result = await authService.socialAuth(await readJson(request));
          return sendJson(response, result.pending ? 202 : 200, { data: result }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/email-verification/request') {
          const actor = await actorResolver.resolve(request.headers);
          const result = await authService.requestEmailVerification(actor.subject);
          return sendJson(response, 200, { data: result }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/email-verification/confirm') {
          const actor = await actorResolver.resolve(request.headers);
          const body = await readJson(request);
          await authService.confirmEmailVerification({ userId: actor.subject, code: body.code });
          return sendJson(response, 200, { data: { verified: true } }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/login') {
          const result = await authService.login(await readJson(request));
          return sendJson(response, 200, { data: result }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/admin-action-token') {
          const actor = await actorResolver.resolve(request.headers);
          const body = await readJson(request);
          const result = await authService.issueAdminActionToken({
            userId: actor.subject,
            credential: body.password,
          });
          return sendJson(response, 200, { data: result }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/logout') {
          const actor = await actorResolver.resolve(request.headers);
          await authService.logout(actor.sessionId);
          return sendJson(response, 200, { data: { loggedOut: true } }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/phone-verification/request') {
          const actor = await actorResolver.resolve(request.headers);
          const result = await authService.requestPhoneVerification(actor.subject);
          return sendJson(response, 200, { data: result }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/phone-verification/confirm') {
          const actor = await actorResolver.resolve(request.headers);
          const body = await readJson(request);
          await authService.confirmPhoneVerification({ userId: actor.subject, code: body.code });
          return sendJson(response, 200, { data: { verified: true } }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/pin-reset/request') {
          const body = await readJson(request);
          const result = await authService.requestPinReset(body.identity);
          return sendJson(response, 200, { data: result }, requestId);
        }
        if (request.method === 'POST' && url.pathname === '/v1/auth/pin-reset/confirm') {
          const body = await readJson(request);
          await authService.confirmPinReset(body);
          return sendJson(response, 200, { data: { reset: true } }, requestId);
        }
      }
      if (authService && request.method === 'GET' && url.pathname === '/v1/me') {
        const actor = await actorResolver.resolve(request.headers);
        return sendJson(response, 200, {
          data: {
            id: actor.subject,
            displayName: actor.displayName,
            role: actor.role,
            roles: actor.roles,
            permissions: actor.permissions ?? [],
          },
        }, requestId);
      }
      if (adminService && url.pathname.startsWith('/v1/admin/')) {
        const resolved = await actorResolver.resolve(request.headers);
        // A valid x-admin-action token (see /v1/auth/admin-action-token) marks
        // the actor as freshly re-authenticated; AdminService requires it for
        // every write and checks the caller's permission first.
        const actor = {
          ...resolved,
          adminActionVerified: await authService.verifyAdminActionToken(
            request.headers['x-admin-action'],
            resolved.subject,
          ),
        };
        const result = await handleAdminRequest({
          method: request.method ?? 'GET',
          url,
          actor,
          adminService,
          readBody: () => readJson(request),
        });
        return sendJson(response, result.status, {
          data: result.data,
          ...(result.total === undefined ? {} : { total: result.total }),
          ...(result.totals === undefined ? {} : { totals: result.totals }),
        }, requestId);
      }
      if (request.method === 'GET' && url.pathname === '/v1/trips') {
        const trips = await tripService.listTrips({ womenOnly: parseWomenOnly(url) });
        return sendJson(response, 200, { data: trips }, requestId);
      }
      if (request.method === 'POST' && url.pathname === '/v1/trips') {
        const actor = await actorResolver.resolve(request.headers);
        const trip = await tripService.postTrip({ actor, input: await readJson(request) });
        return sendJson(response, 201, { data: trip }, requestId);
      }
      if (request.method === 'GET' && url.pathname === '/v1/me/reservations') {
        const actor = await actorResolver.resolve(request.headers);
        const bookings = await tripService.listBookings({ actor });
        return sendJson(response, 200, { data: bookings }, requestId);
      }
      if (request.method === 'GET' && url.pathname === '/v1/me/notifications') {
        const actor = await actorResolver.resolve(request.headers);
        const notifications = await tripService.listNotifications({ actor });
        return sendJson(response, 200, { data: notifications }, requestId);
      }
      if (request.method === 'POST' && url.pathname === '/v1/me/notifications/read') {
        const actor = await actorResolver.resolve(request.headers);
        const markedRead = await tripService.markNotificationsRead({ actor });
        return sendJson(response, 200, { data: { markedRead } }, requestId);
      }
      if (request.method === 'GET' && url.pathname === '/v1/driver/trips') {
        const actor = await actorResolver.resolve(request.headers);
        const summaries = await tripService.listDriverSummaries({ actor });
        return sendJson(response, 200, { data: summaries }, requestId);
      }
      const cancellationMatch = url.pathname.match(/^\/v1\/me\/reservations\/([^/]+)$/);
      if (request.method === 'DELETE' && cancellationMatch) {
        const actor = await actorResolver.resolve(request.headers);
        const result = await tripService.cancelBooking({
          actor,
          reservationId: decodeURIComponent(cancellationMatch[1]),
        });
        return sendJson(response, 200, {
          data: { ...result.reservation, idempotentReplay: result.replayed },
        }, requestId);
      }
      const reservationMatch = url.pathname.match(/^\/v1\/trips\/([^/]+)\/reservations$/);
      if (request.method === 'POST' && reservationMatch) {
        const actor = await actorResolver.resolve(request.headers);
        const result = await tripService.requestSeat({
          actor,
          tripId: decodeURIComponent(reservationMatch[1]),
          input: await readJson(request),
          idempotencyKey: request.headers['idempotency-key'],
        });
        return sendJson(response, result.replayed ? 200 : 201, {
          data: { ...result.reservation, idempotentReplay: result.replayed },
        }, requestId);
      }
      throw notFound('Route not found.');
    } catch (error) {
      const known = error instanceof AppError;
      const safeError = known
        ? error
        : new AppError({ code: 'internal_error', message: 'An unexpected error occurred.', status: 500 });
      if (!known) console.error({ requestId, error });
      return sendJson(response, safeError.status, {
        error: {
          code: safeError.code,
          message: safeError.message,
          ...(safeError.details ? { details: safeError.details } : {}),
        },
      }, requestId);
    }
  });
}
