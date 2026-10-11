import { siteURL } from '../lib/site.mjs';

export default function robots() {
  const url = siteURL();
  return { rules: { userAgent: '*', allow: '/', disallow: ['/r/', '/privacy', '/terms'] },
    ...(url ? { sitemap: new URL('/sitemap.xml', url).href } : {}) };
}
