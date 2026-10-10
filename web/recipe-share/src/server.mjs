// Developer: gengyun
// Purpose: Render unlisted public recipes without following unsafe API redirects.

import { createServer } from 'node:http';
import { isIP } from 'node:net';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { renderRecipePage, renderUnavailable } from './page.mjs';
import { readPublicRecipeJSON } from './public-api.mjs';

function configuredAPI() {
  const raw = process.env.RECIPE_PALS_PUBLIC_RECIPE_API;
  if (!raw || raw.length > 2_048 || raw.trim() !== raw ||
      /[\u0000-\u001f\u007f-\u009f\\?#]/.test(raw)) {
    return null;
  }

  // URL drops a default :443 port, so inspect the original authority first.
  const authority = /^https:\/\/([^/?#]+)/i.exec(raw)?.[1];
  if (!authority || authority.includes(':') || authority.includes('@')) {
    return null;
  }

  try {
    const url = new URL(raw);
    const host = url.hostname.toLowerCase();
    const labels = host.split('.');
    const isPublicHostShape = labels.length >= 2 &&
      labels.every(label => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label)) &&
      /[a-z]/.test(labels.at(-1)) &&
      isIP(host) === 0 &&
      !['.local', '.localhost', '.internal'].some(suffix => host.endsWith(suffix));

    if (url.protocol !== 'https:' || !isPublicHostShape || url.username ||
        url.password || url.port || url.search || url.hash ||
        /\/{2,}$/.test(url.pathname)) {
      return null;
    }

    return url.href.replace(/\/$/, '');
  } catch {
    return null;
  }
}

export function createRecipeServer({
  loadRecipe = null,
  appStoreURL = process.env.RECIPE_PALS_APP_STORE_URL,
} = {}) {
  return createServer(async (req, res) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Cache-Control', 'private, no-store, max-age=0');
    res.setHeader('Content-Security-Policy',
      "default-src 'none'; style-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");

    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.writeHead(405).end();
      return;
    }
    if (req.url === '/styles.css') {
      const css = await readFile(new URL('./styles.css', import.meta.url), 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/css; charset=utf-8' })
        .end(req.method === 'HEAD' ? '' : css);
      return;
    }

    let pathname;
    try {
      pathname = new URL(req.url ?? '/', 'http://placeholder.invalid').pathname;
    } catch {
      // Treat malformed raw request targets as unknown routes, not rejected promises.
      pathname = '';
    }
    const match = pathname.match(/^\/r\/([A-Za-z0-9_-]{8,128})$/);
    if (!match) {
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' })
        .end(renderUnavailable());
      return;
    }

    try {
      let recipe;
      if (loadRecipe) {
        recipe = await loadRecipe(match[1]);
      } else {
        const api = configuredAPI();
        if (!api) {
          res.writeHead(503, { 'Content-Type': 'text/html; charset=utf-8' })
            .end(renderUnavailable(503));
          return;
        }

        // A 30x from even a trusted HTTPS host must never reach private networks.
        const response = await fetch(`${api}/${encodeURIComponent(match[1])}`, {
          headers: { Accept: 'application/json' },
          cache: 'no-store',
          redirect: 'error',
          signal: AbortSignal.timeout(8_000),
        });
        if ([404, 410].includes(response.status)) {
          res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' })
            .end(renderUnavailable());
          return;
        }
        if (!response.ok) throw new Error('Public API unavailable');
        recipe = await readPublicRecipeJSON(response);
      }

      if (!recipe) {
        res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' })
          .end(renderUnavailable());
        return;
      }
      const page = renderRecipePage(recipe, { appStoreURL });
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
        .end(req.method === 'HEAD' ? '' : page);
    } catch {
      res.writeHead(503, { 'Content-Type': 'text/html; charset=utf-8' })
        .end(renderUnavailable(503));
    }
  });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  createRecipeServer().listen(Number(process.env.PORT || 3000));
}
