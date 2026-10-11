import { configuredAPI } from './recipe-server.mjs';
import { readPublicRecipeJSON } from './public-api.mjs';
import { renderRecipePage, renderUnavailable } from './public-recipe.mjs';
import { isValidShareToken } from './referrals.mjs';

const headers = {
  'Content-Type': 'text/html; charset=utf-8',
  'Cache-Control': 'private, no-store, max-age=0',
  'X-Robots-Tag': 'noindex, nofollow, noarchive',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Content-Security-Policy': "default-src 'none'; style-src 'self'; font-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
};

function websiteHTML(html) {
  return html.replace('href="/styles.css"', 'href="/share.css"')
    .replace('<span class="eyebrow">From a shared recipe</span>', '')
    .replace('<body>', '<body><a class="skip-link" href="#main">Skip to content</a>')
    .replace('<header class="brand">✦ RECIPE PALS</header>', '<header class="brand"><a href="/">Recipe Pals</a><a class="download-link" href="/download">Get the app</a></header>')
    .replace('<main>', '<main id="main">')
    .replace('</body>', '<nav class="legal-links" aria-label="Website navigation"><a href="/">Home</a><a href="/privacy">Privacy policy</a><a href="/terms">Terms of use</a></nav></body>');
}

// No cache or redirects: every visit observes upstream revocation status.
export async function shareResponse(slug, { api = process.env.RECIPE_PALS_PUBLIC_RECIPE_API,
  appStoreURL = null, fetcher = fetch } = {}) {
  let status = 404;
  let html;
  if (isValidShareToken(slug)) {
    const base = configuredAPI(api);
    status = 503;
    if (base) {
      try {
        const response = await fetcher(`${base}/${slug}`, {
          headers: { Accept: 'application/json' }, cache: 'no-store', redirect: 'error',
          signal: AbortSignal.timeout(8000),
        });
        if ([404, 410].includes(response.status)) {
          await response.body?.cancel();
          status = 404;
        } else if (response.ok) {
          const recipe = await readPublicRecipeJSON(response);
          html = renderRecipePage(recipe, { appStoreURL });
          status = 200;
        } else {
          await response.body?.cancel();
        }
      } catch {
        status = 503;
      }
    }
  }
  html ??= renderUnavailable(status);
  if (status === 503) {
    html = html.replace('This recipe is private, withdrawn or unavailable. No account or download is required to view available public recipes.',
      'The recipe service is temporarily unavailable. Try opening the same link again later.');
  }
  return new Response(websiteHTML(html), { status, headers });
}
