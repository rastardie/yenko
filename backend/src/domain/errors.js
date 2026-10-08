export class AppError extends Error {
  constructor({ code, message, status, details }) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.status = status;
    this.details = details;
  }
}

export const badRequest = (message, details) =>
  new AppError({ code: 'invalid_request', message, status: 400, details });

export const unauthorized = (message = 'Authentication is required.') =>
  new AppError({ code: 'unauthorized', message, status: 401 });

export const forbidden = (message) =>
  new AppError({ code: 'forbidden', message, status: 403 });

export const notFound = (message) =>
  new AppError({ code: 'not_found', message, status: 404 });

export const conflict = (message, details) =>
  new AppError({ code: 'conflict', message, status: 409, details });

export const adminActionRequired = () =>
  new AppError({
    code: 'admin_action_required',
    message: 'Confirm this action with your password or PIN.',
    status: 403,
  });

export const tooManyAttempts = (message = 'Too many failed attempts. Try again in a few minutes.') =>
  new AppError({ code: 'too_many_attempts', message, status: 429 });
