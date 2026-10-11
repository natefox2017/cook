import { shareResponse } from '../../../lib/share.mjs';
import { storeURL } from '../../../lib/site.mjs';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export async function GET(request, { params }) {
  const { slug } = await params;
  if (new URL(request.url).pathname !== `/r/${slug}`) return shareResponse(null);
  return shareResponse(slug, { appStoreURL: storeURL() });
}
