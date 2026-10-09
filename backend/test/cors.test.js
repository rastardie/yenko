import assert from 'node:assert/strict';
import test from 'node:test';

import { createApp } from '../src/app.js';

/**
 * The deployed PWA (Cloudflare Pages) and this API (Railway) are different
 * origins, so without correct CORS headers the browser rejects every
 * request before application code runs at all. corsOrigins is an exact
 * allow-list, no wildcard — see interfaces/http-server.js.
 */

async function withServer(corsOrigins, run) {
  const server = createApp({ environment: 'test', corsOrigins });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  try {
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  }
}

test('an allow-listed origin receives CORS headers and a working preflight', async () => {
  await withServer(['https://yenko.pages.dev'], async (baseUrl) => {
    const preflight = await fetch(`${baseUrl}/v1/trips`, {
      method: 'OPTIONS',
      headers: { origin: 'https://yenko.pages.dev', 'access-control-request-method': 'GET' },
    });
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get('access-control-allow-origin'), 'https://yenko.pages.dev');
    assert.ok(preflight.headers.get('access-control-allow-methods').includes('GET'));

    const response = await fetch(`${baseUrl}/v1/trips`, {
      headers: { origin: 'https://yenko.pages.dev' },
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('access-control-allow-origin'), 'https://yenko.pages.dev');
    assert.equal(response.headers.get('vary'), 'Origin');
  });
});

test('an origin not on the allow-list gets no CORS headers (the browser blocks it)', async () => {
  await withServer(['https://yenko.pages.dev'], async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/trips`, {
      headers: { origin: 'https://evil.example' },
    });
    // The request still succeeds at the HTTP layer (Node has no concept of
    // CORS enforcement - only browsers enforce it, by checking the
    // response header this server intentionally omits here), but no
    // allow-origin header is present, so a real browser would discard the
    // response rather than hand it to page script.
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('access-control-allow-origin'), null);
  });
});

test('with no CORS_ORIGINS configured, no cross-origin headers are ever sent', async () => {
  await withServer([], async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/trips`, {
      headers: { origin: 'https://yenko.pages.dev' },
    });
    assert.equal(response.headers.get('access-control-allow-origin'), null);
  });
});

test('a same-origin request (no Origin header) is unaffected either way', async () => {
  await withServer(['https://yenko.pages.dev'], async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/trips`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('access-control-allow-origin'), null);
  });
});
