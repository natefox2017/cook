/** Safe recursive cleanup for one user's private Storage objects. */

import { AppError } from "./errors.ts";
import { log } from "./logger.ts";

const PAGE = 100;

export interface StoragePurgeClient {
  storage: {
    from(bucket: string): {
      list(
        prefix: string,
        options: { limit: number; offset: number },
      ): Promise<{
        data: Array<{ id: string | null; name: string }> | null;
        error: { message: string } | null;
      }>;
      remove(paths: string[]): Promise<{ error: { message: string } | null }>;
    };
  };
}

async function collectPaths(
  client: StoragePurgeClient,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const paths: string[] = [];
  for (let offset = 0;; offset += PAGE) {
    const { data: entries, error } = await client.storage
      .from(bucket)
      .list(prefix, { limit: PAGE, offset });
    if (error) {
      log("error", "storage_list_failed", {
        bucket,
        prefix,
        message: error.message,
      });
      throw new AppError(
        "internal_error",
        "An unexpected error occurred",
        500,
      );
    }
    if (!entries?.length) break;

    for (const entry of entries) {
      const path = prefix ? `${prefix}/${entry.name}` : entry.name;
      // Storage marks folders with a null id; only files are removable paths.
      if (entry.id === null) {
        paths.push(...await collectPaths(client, bucket, path));
      } else {
        paths.push(path);
      }
    }

    if (entries.length < PAGE) break;
  }
  return paths;
}

export async function purgeUserStorage(
  client: StoragePurgeClient,
  userId: string,
  buckets: readonly string[],
): Promise<void> {
  for (const bucket of buckets) {
    const paths = await collectPaths(client, bucket, userId);
    for (let offset = 0; offset < paths.length; offset += PAGE) {
      const chunk = paths.slice(offset, offset + PAGE);
      const { error } = await client.storage.from(bucket).remove(chunk);
      if (error) {
        log("error", "storage_remove_failed", {
          bucket,
          message: error.message,
          count: chunk.length,
        });
        throw new AppError(
          "internal_error",
          "An unexpected error occurred",
          500,
        );
      }
    }
  }
}
