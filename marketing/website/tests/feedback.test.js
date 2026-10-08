import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { onRequest } from '../functions/api/feedback.js';
import { validateDraft } from '../dist/feedback/feedback.js';

const API_URL = 'https://typefield.app/api/feedback';
const valid = {
  category: 'bug',
  title: 'Export loses a counter',
  description: 'The inner contour disappears when I export this test glyph.',
  steps: 'Draw an O, export it, then reopen the font.',
  email: '',
  turnstileToken: 'verified-token',
};

function database(fail = false) {
  const calls = [];
  return {
    calls,
    prepare(sql) {
      return {
        bind(...values) {
          calls.push({ sql, values });
          return { async run() { if (fail) throw new Error('database down'); } };
        },
      };
    },
  };
}

function context(body = valid, options = {}) {
  const db = options.db || database();
  const request = new Request(API_URL, {
    method: options.method || 'POST',
    headers: {
      'content-type': options.contentType || 'application/json',
      origin: options.origin || 'https://typefield.app',
    },
    body: JSON.stringify(body),
  });
  return { request, env: { FEEDBACK_DB: db, TURNSTILE_SITE_KEY: 'public-key', TURNSTILE_SECRET_KEY: 'private-key' }, db };
}

function mockVerification(t, result = { success: true, action: 'feedback', hostname: 'typefield.app' }) {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls++;
    assert.equal(url, 'https://challenges.cloudflare.com/turnstile/v0/siteverify');
    assert.equal(options.body.get('secret'), 'private-key');
    assert.equal(options.body.get('response'), 'verified-token');
    return Response.json(result);
  });
  return () => calls;
}

test('client form requires useful bug details and validates optional email', () => {
  assert.equal(validateDraft(valid), null);
  assert.equal(validateDraft({ ...valid, steps: 'short' }).field, 'steps');
  assert.equal(validateDraft({ ...valid, category: 'feedback', steps: '' }), null);
  assert.equal(validateDraft({ ...valid, description: 'too short' }).field, 'description');
  assert.equal(validateDraft({ ...valid, email: 'bad-address' }).field, 'email');
  assert.equal(validateDraft({ ...valid, category: 'other' }).field, 'category');
});

test('GET exposes only the public widget key when all bindings are ready', async () => {
  const { env } = context();
  const response = await onRequest({ request: new Request(API_URL), env });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { siteKey: 'public-key' });
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.equal((await onRequest({ request: new Request(API_URL), env: { ...env, FEEDBACK_DB: undefined } })).status, 503);
});

test('verified, bounded report is inserted once with no IP or token stored', async t => {
  const calls = mockVerification(t);
  const { request, env, db } = context();
  const response = await onRequest({ request, env });
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { ok: true });
  assert.equal(calls(), 1);
  assert.equal(db.calls.length, 1);
  assert.match(db.calls[0].sql, /INSERT INTO feedback_reports/);
  assert.deepEqual(db.calls[0].values.slice(2), [valid.category, valid.title, valid.description, valid.steps, null]);
  assert.ok(!db.calls[0].values.includes(valid.turnstileToken));
});

test('rejects malformed, oversized and file-like submissions before Turnstile or D1', async t => {
  const calls = mockVerification(t);
  for (const [body, status] of [
    [{ ...valid, title: 'tiny' }, 400],
    [{ ...valid, category: 'account' }, 400],
    [{ ...valid, email: 'not-an-email' }, 400],
    [{ ...valid, fontFile: 'base64-font-data' }, 400],
    [{ ...valid, description: 'a'.repeat(17000) }, 413],
  ]) {
    const { request, env, db } = context(body);
    assert.equal((await onRequest({ request, env })).status, status);
    assert.equal(db.calls.length, 0);
  }
  const { env, db } = context();
  const multipart = new Request(API_URL, { method: 'POST', headers: { 'content-type': 'multipart/form-data' }, body: 'file' });
  assert.equal((await onRequest({ request: multipart, env })).status, 415);
  assert.equal(db.calls.length, 0);
  assert.equal(calls(), 0);
  const malformed = new Request(API_URL, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{' });
  assert.equal((await onRequest({ request: malformed, env })).status, 400);
  assert.equal(calls(), 0);
});

test('requires same origin and matching Turnstile action and hostname', async t => {
  const calls = mockVerification(t, { success: true, action: 'login', hostname: 'other.example' });
  const { request, env, db } = context();
  assert.equal((await onRequest({ request, env })).status, 400);
  assert.equal(db.calls.length, 0);
  assert.equal(calls(), 1);
  const foreign = context(valid, { origin: 'https://other.example' });
  assert.equal((await onRequest({ request: foreign.request, env: foreign.env })).status, 403);
  assert.equal(calls(), 1);
});

test('rejects failed verification, wrong action and wrong hostname independently', async t => {
  const results = [
    { success: false, action: 'feedback', hostname: 'typefield.app' },
    { success: true, action: 'login', hostname: 'typefield.app' },
    { success: true, action: 'feedback', hostname: 'other.example' },
  ];
  t.mock.method(globalThis, 'fetch', async () => Response.json(results.shift()));
  for (let i = 0; i < 3; i++) {
    const { request, env, db } = context();
    assert.equal((await onRequest({ request, env })).status, 400);
    assert.equal(db.calls.length, 0);
  }
});

test('database failure returns a retryable error without claiming success', async t => {
  mockVerification(t);
  const { request, env } = context(valid, { db: database(true) });
  const response = await onRequest({ request, env });
  assert.equal(response.status, 503);
  assert.match((await response.json()).error, /could not be saved/);
});

test('site links, privacy copy and release assets stay aligned', () => {
  for (const page of ['index.html', 'features/index.html', 'download/index.html']) {
    const html = readFileSync(new URL(`../dist/${page}`, import.meta.url), 'utf8');
    assert.doesNotMatch(html, /typefield-feedback\/issues\/new/);
    assert.match(html, /href="\/feedback\//);
    assert.match(html, /<link rel="canonical" href="https:\/\/typefield\.app\//);
    assert.match(html, /<meta property="og:image" content="https:\/\/typefield\.app\/assets\/social-preview-v2\.png">/);
  }
  const feedback = readFileSync(new URL('../dist/feedback/index.html', import.meta.url), 'utf8');
  assert.match(feedback, /<link rel="canonical" href="https:\/\/typefield\.app\/feedback\/">/);
  for (const name of ['category', 'title', 'description', 'steps', 'email']) {
    assert.match(feedback, new RegExp(`name="${name}"`));
    assert.match(feedback, new RegExp(`for="${name}"`));
  }
  assert.match(feedback, /Cloudflare Turnstile checks submissions/);
  assert.doesNotMatch(feedback, /type="file"/);
  const download = readFileSync(new URL('../dist/download/index.html', import.meta.url), 'utf8');
  const plist = readFileSync(new URL('../../../Resources/Info.plist', import.meta.url), 'utf8');
  const version = plist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)[1];
  const build = plist.match(/<key>CFBundleVersion<\/key>\s*<string>([^<]+)<\/string>/)[1];
  const filename = `Typefield-${version}-beta.dmg`;
  const currentHash = download.match(/SHA-256: <code>([a-f0-9]{64})<\/code>/)[1];
  const actualCurrentHash = createHash('sha256').update(readFileSync(new URL(`../dist/assets/${filename}`, import.meta.url))).digest('hex');
  assert.equal(actualCurrentHash, currentHash);
  const priorHash = 'b88c47307013e4e255ad9a37cd586344d53354e7ce2a0f6675843ef570b7c79f';
  const actualPriorHash = createHash('sha256').update(readFileSync(new URL('../dist/assets/Typefield-0.59.8-beta.dmg', import.meta.url))).digest('hex');
  assert.equal(actualPriorHash, priorHash);
  assert.ok(download.includes(`Version ${version} beta 1 (build ${build})`));
  assert.ok(download.includes(`class="download-button" href="../assets/${filename}"`));
  assert.ok(download.includes(`releases/download/v${version}-beta.1/${filename}`));
  assert.doesNotMatch(download, /class="download-button" href="\.\.\/assets\/Typefield-0\.59\.8-beta\.dmg"/);
  const headers = readFileSync(new URL('../dist/_headers', import.meta.url), 'utf8');
  assert.ok(headers.includes(`/assets/${filename}\n  Content-Type: application/x-apple-diskimage\n  Content-Disposition: attachment; filename="${filename}"`));

});
