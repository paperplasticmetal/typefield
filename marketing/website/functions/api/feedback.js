const MAX_BODY_BYTES = 16 * 1024;
const MAX_TURNSTILE_TOKEN_LENGTH = 2048;
const CATEGORIES = new Set(['feedback', 'bug']);
const FIELD_NAMES = new Set(['category', 'title', 'description', 'steps', 'email', 'turnstileToken']);

function json(data, status = 200, extraHeaders = {}) {
  return Response.json(data, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      ...extraHeaders,
    },
  });
}

class InputError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

async function readBoundedJson(request) {
  const declaredLength = Number(request.headers.get('content-length'));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    throw new InputError(413, 'too_large', 'The report is too long. Shorten it and try again.');
  }
  if (!request.body) throw new InputError(400, 'invalid_body', 'Enter a report and try again.');

  const reader = request.body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let bytes = 0;
  let text = '';
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > MAX_BODY_BYTES) {
        await reader.cancel();
        throw new InputError(413, 'too_large', 'The report is too long. Shorten it and try again.');
      }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    return JSON.parse(text);
  } catch (error) {
    if (error instanceof InputError) throw error;
    throw new InputError(400, 'invalid_body', 'The report could not be read. Try again.');
  } finally {
    reader.releaseLock();
  }
}

function field(value, name, min, max, required = true) {
  if (value === undefined && !required) return '';
  if (typeof value !== 'string') {
    throw new InputError(400, 'invalid_fields', `Check the ${name} field and try again.`);
  }
  const clean = value.trim();
  if ((required && clean.length < min) || clean.length > max) {
    throw new InputError(400, 'invalid_fields', `Check the ${name} field and try again.`);
  }
  return clean;
}

function validate(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      Object.keys(input).some(key => !FIELD_NAMES.has(key))) {
    throw new InputError(400, 'invalid_fields', 'Check the report fields and try again.');
  }
  const category = field(input.category, 'category', 1, 20);
  if (!CATEGORIES.has(category)) {
    throw new InputError(400, 'invalid_fields', 'Choose a report category.');
  }
  const title = field(input.title, 'subject', 5, 120);
  const description = field(input.description, 'description', 20, 4000);
  const steps = field(input.steps, 'steps to reproduce', category === 'bug' ? 10 : 0, 2000, category === 'bug');
  const email = field(input.email, 'email', 0, 254, false);
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new InputError(400, 'invalid_fields', 'Enter a valid email address or leave it blank.');
  }
  const turnstileToken = field(input.turnstileToken, 'verification', 1, MAX_TURNSTILE_TOKEN_LENGTH);
  return { category, title, description, steps, email: email || null, turnstileToken };
}

async function verifyTurnstile(request, secret, token) {
  const body = new FormData();
  body.set('secret', secret);
  body.set('response', token);
  const remoteIp = request.headers.get('CF-Connecting-IP');
  if (remoteIp) body.set('remoteip', remoteIp);
  let response;
  try {
    response = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      body,
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return false;
    const result = await response.json();
    return result.success === true && result.action === 'feedback' &&
      result.hostname === new URL(request.url).hostname;
  } catch {
    return false;
  }
}

export async function onRequest({ request, env }) {
  if (request.method === 'GET') {
    if (!env.TURNSTILE_SITE_KEY || !env.TURNSTILE_SECRET_KEY || !env.FEEDBACK_DB) {
      return json({ error: 'Feedback is temporarily unavailable.' }, 503);
    }
    return json({ siteKey: env.TURNSTILE_SITE_KEY });
  }
  if (request.method !== 'POST') {
    return json({ error: 'Method not allowed.' }, 405, { Allow: 'GET, POST' });
  }
  if (!env.TURNSTILE_SECRET_KEY || !env.FEEDBACK_DB) {
    return json({ error: 'Feedback is temporarily unavailable.' }, 503);
  }
  const origin = request.headers.get('origin');
  if (origin && origin !== new URL(request.url).origin) {
    return json({ error: 'Please submit this form from the Typefield website.' }, 403);
  }
  if (!/^application\/json(?:\s*;|\s*$)/i.test(request.headers.get('content-type') || '')) {
    return json({ error: 'This form requires a JSON request.' }, 415);
  }

  try {
    const report = validate(await readBoundedJson(request));
    if (!await verifyTurnstile(request, env.TURNSTILE_SECRET_KEY, report.turnstileToken)) {
      return json({ error: 'Verification failed or expired. Try again.' }, 400);
    }
    await env.FEEDBACK_DB.prepare(
      'INSERT INTO feedback_reports (id, created_at, category, title, description, steps, reporter_email) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).bind(
      crypto.randomUUID(), new Date().toISOString(), report.category, report.title,
      report.description, report.steps, report.email
    ).run();
    return json({ ok: true }, 201);
  } catch (error) {
    if (error instanceof InputError) return json({ error: error.message, code: error.code }, error.status);
    return json({ error: 'The report could not be saved. Please try again later.' }, 503);
  }
}
