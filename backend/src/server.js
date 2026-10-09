import { createRuntimeApp } from './app.js';

const port = Number.parseInt(process.env.PORT ?? process.env.API_PORT ?? '8080', 10);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT must be an integer between 1 and 65535.');

const runtime = await createRuntimeApp({
  environment: process.env.NODE_ENV ?? 'development',
  databaseUrl: process.env.DATABASE_URL,
  authMode: process.env.AUTH_MODE,
  jwtSecret: process.env.JWT_SECRET,
  signupApproval: process.env.SIGNUP_APPROVAL,
  oidcIssuer: process.env.OIDC_ISSUER,
  oidcAudience: process.env.OIDC_AUDIENCE,
  oidcRolesClaim: process.env.OIDC_ROLES_CLAIM,
  enableEmailMailer: process.env.MAIL_ENABLED === 'true',
  webauthnRpID: process.env.WEBAUTHN_RP_ID,
  webauthnOrigin: process.env.WEBAUTHN_ORIGIN,
  // Exact HTTPS origin(s) the deployed PWA is served from (e.g. Cloudflare
  // Pages), comma-separated. No wildcard — see interfaces/http-server.js.
  // Empty/unset means the web client cannot call this API cross-origin at
  // all, which is correct for a backend only ever called by native apps.
  corsOrigins: (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
  env: process.env,
});

const host = process.env.API_HOST ?? '0.0.0.0';
runtime.server.listen(port, host, () => console.log(`YɛnKɔ API listening on http://${host}:${port}`));

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => runtime.server.close(async () => {
    await runtime.close();
    process.exit(0);
  }));
}
