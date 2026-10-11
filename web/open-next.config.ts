import { defineCloudflareConfig } from '@opennextjs/cloudflare';
import staticAssetsIncrementalCache from '@opennextjs/cloudflare/overrides/incremental-cache/static-assets-incremental-cache';

// Only build-time pages are cached. Recipe snapshots always use no-store.
export default defineCloudflareConfig({
  incrementalCache: staticAssetsIncrementalCache,
});
