import { siteURL } from '../lib/site.mjs';

export default function sitemap() {
  const url = siteURL();
  return url ? ['/', '/download'].map(path => ({ url: new URL(path, url).href })) : [];
}
