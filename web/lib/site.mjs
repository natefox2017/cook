import { safeStoreURL } from './public-recipe.mjs';

export function storeURL() {
  return safeStoreURL(process.env.RECIPE_PALS_APP_STORE_URL);
}

export function siteURL() {
  try {
    const url = new URL(process.env.RECIPE_PALS_SITE_URL);
    if (url.protocol !== 'https:' || url.username || url.password || url.port ||
        url.pathname !== '/' || url.search || url.hash) return null;
    return url;
  } catch {
    return null;
  }
}
