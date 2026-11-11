/**
 * ExamVault edge API.
 *
 * One worker in front of one R2 bucket. There is no database and no origin
 * server — which is the entire point: at 09:12 on result day there is nothing
 * here that can fall over.
 *
 * Routes
 *   GET /v1/live_feed_v1.json           radar document      s-maxage=0 (deliberately not edge-cached)
 *   GET /v1/rolls/:examId_rolls.json.gz sorted roll index   s-maxage=86400, immutable
 *   GET /v1/pdf/:examId_result.pdf      mirrored result PDF s-maxage=86400
 *   GET /r/:examId                      302 → the exam's official result link, 60 s cache
 *   GET /health                         liveness            no-store
 *
 * Why the cache headers matter more than the code:
 *   Cloudflare collapses every concurrent request for the same cache key into a
 *   single origin fetch ("request collapsing"). For the content-addressed roll
 *   indexes (s-maxage=86400) the R2 bucket is read once per day per PoP no
 *   matter whether 10 users or 10 million ask. The 1 KB feed is deliberately
 *   NOT edge-cached (see its route) so a publish is visible immediately;
 *   request collapsing still turns a burst into a handful of R2 reads. That
 *   combination is what turns a free-tier account into a 10M-CCU CDN.
 */

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,HEAD,OPTIONS',
  'access-control-allow-headers': 'If-None-Match,Content-Type',
  'access-control-max-age': '86400',
};

const FEED_KEY = 'v1/live_feed_v1.json';

/** Attach the headers that make the edge do the work. */
function withCache(headers, { maxAge, sMaxAge, immutable = false, contentType }) {
  const out = new Headers(headers);
  // `immutable` is a Cache-Control *directive*, not a standalone header. It was
  // previously emitted as `immutable: true`, which every client ignores — so
  // the content-addressed roll routes never actually got "don't revalidate for
  // max-age" behaviour. Only the rolls route sets the flag, and only there is
  // it correct: the URL carries a content hash, so new content always arrives
  // at a new URL.
  const directives = ['public', `max-age=${maxAge}`, `s-maxage=${sMaxAge}`];
  if (immutable) directives.push('immutable');
  out.set('cache-control', directives.join(', '));
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
    key: () => FEED_KEY,
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

/**
 * GET /r/:examId — the deep link printed on the share card.
 *
 * The project owns no domain, so EV_WEB_BASE points at this worker and /r/ is
 * the route that makes the printed link real: it looks the exam up in the live
 * feed (the same 1 KB R2 object the app reads) and 302s to the commission's
 * own PDF or notice page. When the exam is not in the feed the answer is a
 * plain-text 404 — a dead end beats an invented redirect.
 *
 * Cached for 60 s: long enough to absorb a share burst, short enough that a
 * freshly published official link goes live within a minute.
 */
async function resultRedirect(examId, { env, ctx, request, url }) {
  const cache = caches.default;
  const cacheKey = new Request(url.toString(), request);
  const cached = await cache.match(cacheKey);
  if (cached) {
    const hit = new Response(cached.body, cached);
    hit.headers.set('x-examvault-cache', 'HIT');
    return hit;
  }

  const shared = {
    ...CORS,
    'cache-control': 'public, max-age=60, s-maxage=60',
  };

  let target = null;
  try {
    const feedObject = await env.EXAMVAULT_BUCKET.get(FEED_KEY);
    if (feedObject) {
      const feed = JSON.parse(await feedObject.text());
      const row = (feed.updates ?? []).find((u) => u && u.exam_id === examId);
      // Prefer the PDF, fall back to the notice page. Never invent a URL:
      // the feed's official_* fields are the only sources of truth.
      target = row?.official_pdf || row?.official_page || null;
    }
  } catch (err) {
    return new Response('Origin unavailable', { status: 502, headers: CORS });
  }

  const response = target
    ? new Response(null, {
        status: 302,
        headers: { ...shared, location: target },
      })
    : new Response('This result link is no longer active.', {
        status: 404,
        headers: { ...shared, 'content-type': 'text/plain; charset=utf-8' },
      });

  // Same discipline as the object routes: a failed put must never fail the
  // request — the next caller simply takes the R2 path again.
  ctx.waitUntil(
    cache.put(cacheKey, response.clone()).catch((err) => {
      console.error('cache.put failed (/r/)', err?.message ?? err);
    }),
  );
  return response;
}

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

    // /r/:examId — share-card deep link; see resultRedirect().
    const redirectMatch = url.pathname.match(/^\/r\/([a-z0-9_]+)$/);
    if (redirectMatch) {
      return resultRedirect(redirectMatch[1], { env, ctx, request, url });
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
      // "not published yet" and tells the user exactly that. There is no local
      // demo index to fall back to — the repository deliberately has no type
      // for one ("Fabricating an exam outcome is unacceptable", see
      // IndexSource in app/lib/data/repositories/result_index_repository.dart),
      // so this path must stay cheap and must not be cached for long.
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
