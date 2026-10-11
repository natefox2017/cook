const adminFunctions = new Set([
  'admin-auth', 'admin-dashboard', 'admin-users', 'admin-subscriptions', 'admin-ai',
]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
    const path = url.pathname.slice('/api/'.length);
    if (!adminFunctions.has(path.split('/')[0])) return new Response('Not found', { status: 404 });

    // Keep custom admin authorization; omit cookies and Origin to avoid browser CORS.
    const headers = new Headers();
    for (const name of ['authorization', 'apikey', 'content-type', 'x-cookapp-bootstrap-token']) {
      const value = request.headers.get(name);
      if (value) headers.set(name, value);
    }
    try {
      const base = new URL(env.ADMIN_FUNCTIONS_URL);
      if (base.protocol !== 'https:' || base.username || base.password || base.search || base.hash) {
        throw new Error('Invalid admin upstream configuration');
      }
      const upstream = await fetch(`${base.href.replace(/\/$/, '')}/${path}${url.search}`, {
        method: request.method,
        headers,
        body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
        redirect: 'manual',
        signal: AbortSignal.timeout(30_000),
      });
      if (upstream.status >= 300 && upstream.status < 400) {
        await upstream.body?.cancel();
        throw new Error('Admin API unexpectedly redirected');
      }
      return new Response(upstream.body, {
        status: upstream.status,
        headers: {
          'Content-Type': upstream.headers.get('Content-Type') || 'application/json',
          'Cache-Control': 'private, no-store',
          'X-Content-Type-Options': 'nosniff',
          'X-Robots-Tag': 'noindex, nofollow, noarchive',
        },
      });
    } catch {
      // Log transport failures only, never submitted bodies or authorization headers.
      console.error('Admin upstream fetch failed');
      return Response.json({ error: { message: 'Admin service temporarily unavailable' } }, {
        status: 502,
        headers: { 'Cache-Control': 'private, no-store' },
      });
    }
  },
};
