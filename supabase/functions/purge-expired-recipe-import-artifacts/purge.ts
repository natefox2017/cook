// Developer: RecipePouch
// Purpose: Bounded, owner-scoped artifact cleanup that can be retried safely.

export const ARTIFACT_CLEANUP_PAGE_SIZE = 100;
export const ARTIFACT_CLEANUP_MAX_ROWS = 1_000;

const BUCKET = "recipe-import-artifacts";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EXPIRED_STATES = new Set(["upload_pending", "available", "rejected"]);

export interface ExpiredArtifact {
  id: string;
  owner_id: string;
  storage_bucket: string;
  storage_path: string;
  state: string;
  expires_at: string;
}

export interface ArtifactPurgeSource {
  /** Read stable ordered pages before changing state; never paginate while deleting. */
  listExpired(cutoff: string, offset: number, limit: number): Promise<ExpiredArtifact[]>;
  remove(path: string): Promise<void>;
  /** Conditional update; return false if another operation changed this row. */
  markExpired(row: ExpiredArtifact, cutoff: string): Promise<boolean>;
}

export interface ArtifactPurgeReport {
  attempted: number;
  expired: number;
  failed: number;
  has_more: boolean;
}

export function securelyEqual(left: string, right: string): boolean {
  // Reject oversized attacker-controlled headers before allocating buffers.
  if (left.length > 512 || right.length > 512) return false;
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let difference = a.length ^ b.length;
  for (let index = 0; index < Math.max(a.length, b.length); index++) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}

export function isPurgeableArtifact(row: ExpiredArtifact, cutoff: string): boolean {
  const cutoffMS = Date.parse(cutoff);
  const expiryMS = Date.parse(row.expires_at);
  return Number.isFinite(cutoffMS) &&
    Number.isFinite(expiryMS) &&
    expiryMS <= cutoffMS &&
    EXPIRED_STATES.has(row.state) &&
    row.storage_bucket === BUCKET &&
    UUID.test(row.id) && UUID.test(row.owner_id) &&
    row.storage_path === `${row.owner_id}/${row.id}`;
}

export async function purgeExpiredArtifacts(
  source: ArtifactPurgeSource,
  cutoff: string = new Date().toISOString(),
): Promise<ArtifactPurgeReport> {
  if (!Number.isFinite(Date.parse(cutoff))) {
    throw new Error("Invalid cleanup cutoff");
  }

  const rows: ExpiredArtifact[] = [];
  // Fetch the complete bounded workset before Storage mutations. An offset
  // query *after* marking earlier rows expired would silently skip others.
  for (
    let offset = 0;
    offset < ARTIFACT_CLEANUP_MAX_ROWS;
    offset += ARTIFACT_CLEANUP_PAGE_SIZE
  ) {
    const page = await source.listExpired(cutoff, offset, ARTIFACT_CLEANUP_PAGE_SIZE);
    if (page.length > ARTIFACT_CLEANUP_PAGE_SIZE) {
      throw new Error("Cleanup source returned an oversized page");
    }
    rows.push(...page);
    if (page.length < ARTIFACT_CLEANUP_PAGE_SIZE) break;
  }

  let expired = 0;
  let failed = 0;
  for (const row of rows) {
    if (!isPurgeableArtifact(row, cutoff)) {
      failed++;
      continue;
    }

    try {
      // Remove first; if Storage is unavailable the row remains retryable.
      // Completion must also compare expires_at during its conditional write
      // so a late upload cannot revive an already expired artifact.
      await source.remove(row.storage_path);
      if (await source.markExpired(row, cutoff)) {
        expired++;
      } else {
        failed++;
      }
    } catch {
      failed++;
    }
  }

  return {
    attempted: rows.length,
    expired,
    failed,
    has_more: rows.length === ARTIFACT_CLEANUP_MAX_ROWS,
  };
}
