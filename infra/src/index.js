/**
 * ExamVault edge API.
 *
 * One worker in front of one R2 bucket. There is no database and no origin
 * server — which is the entire point: at 09:12 on result day there is nothing
 * here that can fall over.
 *
 * Routes
 *   GET /v1/live_feed_v1.json          radar document      s-maxage=3600
 *   GET /v1/rolls/:examId_rolls.json.gz sorted roll index  s-maxage=86400, immutable
 *   GET /v1/pdf/:examId_result.pdf     mirrored result PDF s-maxage=86400
 *   GET /health                        liveness            no-store
 *
 * Why the cache headers matter more than the code:
 *   Cloudflare collapses every concurrent request for the same cache key into a
 *   single origin fetch ("request collapsing"). With s-maxage=3600 the R2 bucket
 *   is read once per hour per PoP no matter whether 10 users or 10 million ask.
 *   That is what turns a free-tier account into a 10M-CCU CDN.
 */

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,HEAD,OPTIONS',
  'access-control-allow-headers': 'If-None-Match,Content-Type',
  'access-control-max-age': '86400',
};

/** Attach the headers that make the edge do the work. */
function withCache(headers, { maxAge, sMaxAge, immutable = false, contentType }) {
  const out = new Headers(headers);
  out.set('cache-control', `public, max-age=${maxAge}, s-maxage=${sMaxAge}`);
  if (immutable) out.set('immutable', 'true');
  if (contentType) out.set('content-type', contentType);
  for (const [k, v] of Object.entries(CORS)) out.set(k, v);
  // Roll indexes change rarely; let the browser keep them for a day too.
  out.set('vary', 'Accept-Encoding');
  return out;
}

const routes = [
  {
    // {1} = examId
    pattern: /^\/v1\/rolls\/([a-z0-9_]+)_rolls\.json\.gz$/,
    key: (m) => `v1/rolls/${m[1]}_rolls.json.gz`,
    // Served as a gzip *object*. `Accept-Encoding: identity` from the client
    // stops the socket from decoding it a second time; the app gunzips inside an
    // isolate where it can be interrupted without dropping a frame.
    contentType: 'application/gzip',
    maxAge: 3600,
    sMaxAge: 86400,
    immutable: true,
    edgeCacheTtl: 86400,
  },
  {
    pattern: /^\/v1\/pdf\/([a-z0-9_]+)_result\.pdf$/,
    key: (m) => `v1/pdf/${m[1]}_result.pdf`,
    contentType: 'application/pdf',
    maxAge: 600,
    sMaxAge: 86400,
    immutable: false,
    edgeCacheTtl: 86400,
  },
  {
    pattern: /^\/v1\/live_feed_v1\.json$/,
    key: () => 'v1/live_feed_v1.json',
    contentType: 'application/json; charset=utf-8',
    // The radar document is ~1 KB and changes the moment a result drops.
    //
    // It is deliberately NOT edge-cached. An earlier version gave it
    // `s-maxage=3600`, which meant a publish could stay invisible for an hour —
    // and because there is no zone behind workers.dev, there is no cache to
    // purge either. One R2 read per request for a 1 KB object costs nothing, and
    // Cloudflare still collapses concurrent requests upstream.
    maxAge: 30,
    sMaxAge: 0,
    immutable: false,
    edgeCacheTtl: 0,
    noEdgeCache: true,
  },
];

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', {
        status: 405,
        headers: { ...CORS, allow: 'GET,HEAD,OPTIONS' },
      });
    }

    if (url.pathname === '/health') {
      return new Response(JSON.stringify({ ok: true, edge: true }), {
        headers: {
          ...CORS,
          'content-type': 'application/json',
          'cache-control': 'no-store',
        },
      });
    }

    const route = routes.find((r) => r.pattern.test(url.pathname));
    if (!route) {
      return new Response('Not found', { status: 404, headers: CORS });
    }

    const match = url.pathname.match(route.pattern);
    const key = route.key(match);

    // Ask the Cache API first. `caches.default` is free and per-PoP, so a hit
    // here never reaches R2 and never costs an operation.
    const cache = caches.default;
    const cacheKey = new Request(url.toString(), request);

    if (!route.noEdgeCache) {
      const cached = await cache.match(cacheKey);
      if (cached) {
        const hit = new Response(cached.body, cached);
        hit.headers.set('x-examvault-cache', 'HIT');
        return hit;
      }
    }

    let object;
    try {
      object = await env.EXAMVAULT_BUCKET.get(key);
    } catch (err) {
      return new Response('Origin unavailable', {
        status: 502,
        headers: CORS,
      });
    }

    if (!object) {
      // 404 is a *valid* answer before a result drops. The app treats it as
      // "not published yet" and falls back to its local demo index, so this path
      // must stay cheap and must not be cached for long.
      return new Response('Not published yet', {
        status: 404,
        headers: { ...CORS, 'cache-control': 'public, max-age=15, s-maxage=15' },
      });
    }

    // Honour conditional requests: a revalidating client gets a 304 and the app
    // keeps its cached bytes. ~200 bytes instead of 150 KB per refresh.
    const etag = object.httpEtag;
    const ifNoneMatch = request.headers.get('if-none-match');
    if (ifNoneMatch && ifNoneMatch === etag) {
      return new Response(null, {
        status: 304,
        headers: {
          ...CORS,
          etag,
          'cache-control': `public, max-age=${route.maxAge}, s-maxage=${route.sMaxAge}`,
        },
      });
    }

    const headers = withCache(new Headers(), route);
    headers.set('etag', etag);
    headers.set(
      'x-examvault-cache',
      route.noEdgeCache ? 'BYPASS' : 'MISS',
    );

    // Buffer first, then hand out copies.
    //
    // A streaming body can only be read once. The previous version returned
    // `new Response(response.body, …)` and *also* put a `clone()` into the cache:
    // the clone shares the same underlying stream, so the put raced the client
    // download and silently lost, leaving every request a MISS. Reading the
    // object once into memory and building two independent Responses fixes it.
    //
    // Roll indexes are <= 12 MB of budget and typically ~150 KB, so buffering is
    // cheaper than a second R2 read.
    const buffer = await object.arrayBuffer();

    const cacheable = new Response(buffer, { status: 200, headers });
    ctx.waitUntil(
      cache.put(cacheKey, cacheable.clone()).catch((err) => {
        // A failed put must never fail the request — the next caller simply
        // takes the origin path again.
        console.error('cache.put failed', err?.message ?? err);
      }),
    );

    if (request.method === 'HEAD') {
      return new Response(null, { status: 200, headers });
    }
    return new Response(buffer, { status: 200, headers });
  },
};
