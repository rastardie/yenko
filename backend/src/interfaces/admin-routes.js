import { badRequest, forbidden, notFound } from '../domain/errors.js';

const parseInteger = (url, name) => {
  const raw = url.searchParams.get(name);
  if (raw === null) return undefined;
  if (!/^\d{1,6}$/.test(raw)) throw badRequest(`${name} must be a non-negative integer.`);
  return Number(raw);
};

const text = (url, name) => url.searchParams.get(name) ?? undefined;

/**
 * Maps `/v1/admin/*` requests to AdminService use cases. Returns
 * `{ status, data, total? }` or throws; the caller serializes it. Permission
 * checks live in AdminService, not here.
 */
export async function handleAdminRequest({ method, url, actor, adminService, readBody }) {
  // Only groups holding admin:access (by default Super Admins and Admins) may
  // use the Admin area at all; the per-action permissions are checked after.
  if (!Array.isArray(actor?.permissions) || !actor.permissions.includes('admin:access')) {
    throw forbidden('The Admin area is only available to the Admins group.');
  }
  const path = url.pathname.replace(/^\/v1\/admin/, '');
  const page = { limit: parseInteger(url, 'limit'), offset: parseInteger(url, 'offset') };
  const list = (result) => ({ status: 200, data: result.items, total: result.total });
  let match;

  if (method === 'GET' && path === '/summary') {
    return { status: 200, data: await adminService.summary(actor) };
  }
  if (method === 'GET' && path === '/metrics') {
    return {
      status: 200,
      data: await adminService.metrics(actor, {
        period: text(url, 'period'), from: text(url, 'from'), to: text(url, 'to'),
      }),
    };
  }
  if (method === 'GET' && path === '/dashboard') {
    return { status: 200, data: await adminService.dashboard(actor) };
  }

  if (path === '/users') {
    if (method === 'GET') {
      return list(await adminService.listUsers(actor, {
        search: text(url, 'search'), status: text(url, 'status'), groupId: text(url, 'groupId'), ...page,
      }));
    }
    if (method === 'POST') {
      return { status: 201, data: await adminService.createUser(actor, await readBody()) };
    }
  }
  if ((match = path.match(/^\/users\/([^/]+)$/))) {
    const id = decodeURIComponent(match[1]);
    if (method === 'GET') return { status: 200, data: await adminService.getUser(actor, id) };
    if (method === 'PATCH') {
      return { status: 200, data: await adminService.updateUser(actor, id, await readBody()) };
    }
  }
  if ((match = path.match(/^\/users\/([^/]+)$/)) && method === 'DELETE') {
    return { status: 200, data: await adminService.deleteUser(actor, decodeURIComponent(match[1])) };
  }
  if ((match = path.match(/^\/users\/([^/]+)\/(approve|deny)$/)) && method === 'POST') {
    const id = decodeURIComponent(match[1]);
    return {
      status: 200,
      data: match[2] === 'approve' ? await adminService.approveUser(actor, id) : await adminService.denyUser(actor, id),
    };
  }
  if ((match = path.match(/^\/users\/([^/]+)\/reset-password$/)) && method === 'POST') {
    return {
      status: 200,
      data: await adminService.resetCredentials(actor, decodeURIComponent(match[1]), await readBody()),
    };
  }

  if (method === 'GET' && path === '/permissions') {
    return { status: 200, data: await adminService.listPermissions(actor) };
  }
  if (path === '/groups') {
    if (method === 'GET') return { status: 200, data: await adminService.listGroups(actor) };
    if (method === 'POST') return { status: 201, data: await adminService.createGroup(actor, await readBody()) };
  }
  if ((match = path.match(/^\/groups\/([^/]+)$/))) {
    const id = decodeURIComponent(match[1]);
    if (method === 'GET') return { status: 200, data: await adminService.getGroup(actor, id) };
    if (method === 'PATCH') {
      return { status: 200, data: await adminService.updateGroup(actor, id, await readBody()) };
    }
    if (method === 'DELETE') return { status: 200, data: await adminService.deleteGroup(actor, id) };
  }
  if ((match = path.match(/^\/groups\/([^/]+)\/permissions$/)) && method === 'PUT') {
    return {
      status: 200,
      data: await adminService.setGroupPermissions(actor, decodeURIComponent(match[1]), await readBody()),
    };
  }
  if ((match = path.match(/^\/groups\/([^/]+)\/members$/)) && method === 'POST') {
    return {
      status: 200,
      data: await adminService.addGroupMember(actor, decodeURIComponent(match[1]), await readBody()),
    };
  }
  if ((match = path.match(/^\/groups\/([^/]+)\/members\/([^/]+)$/)) && method === 'DELETE') {
    return {
      status: 200,
      data: await adminService.removeGroupMember(
        actor, decodeURIComponent(match[1]), decodeURIComponent(match[2]),
      ),
    };
  }

  if (method === 'GET' && path === '/trips') {
    return list(await adminService.listTrips(actor, { status: text(url, 'status'), ...page }));
  }
  if ((match = path.match(/^\/trips\/([^/]+)$/)) && method === 'GET') {
    return { status: 200, data: await adminService.getTrip(actor, decodeURIComponent(match[1])) };
  }
  if ((match = path.match(/^\/trips\/([^/]+)\/cancel$/)) && method === 'POST') {
    return { status: 200, data: await adminService.cancelTrip(actor, decodeURIComponent(match[1])) };
  }

  if (method === 'GET' && (path === '/bookings' || path === '/reports/bookings')) {
    const filters = {
      from: text(url, 'from'), to: text(url, 'to'), status: text(url, 'status'),
      womenOnly: text(url, 'womenOnly'), search: text(url, 'search'), ...page,
    };
    const result = path === '/bookings'
      ? await adminService.listBookings(actor, filters)
      : await adminService.bookingReport(actor, filters);
    return { status: 200, data: result.items, total: result.total, totals: result.totals };
  }
  if ((match = path.match(/^\/bookings\/([^/]+)\/(confirm|cancel)$/)) && method === 'POST') {
    const id = decodeURIComponent(match[1]);
    return {
      status: 200,
      data: match[2] === 'confirm' ? await adminService.confirmBooking(actor, id) : await adminService.cancelBooking(actor, id),
    };
  }

  if (method === 'GET' && path === '/audit-logs/actions') {
    return { status: 200, data: await adminService.auditActions(actor) };
  }
  if (method === 'GET' && path === '/audit-logs') {
    return list(await adminService.listAudit(actor, {
      action: text(url, 'action'), actorId: text(url, 'actorId'), ...page,
    }));
  }

  throw notFound('Route not found.');
}
