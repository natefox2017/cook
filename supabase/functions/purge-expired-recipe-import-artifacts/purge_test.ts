// Developer: RecipePouch
// Purpose: Isolated cleanup regression tests; no Supabase credentials or network calls.

import {
  ARTIFACT_CLEANUP_MAX_ROWS,
  ARTIFACT_CLEANUP_PAGE_SIZE,
  isPurgeableArtifact,
  purgeExpiredArtifacts,
  securelyEqual,
  type ArtifactPurgeSource,
  type ExpiredArtifact,
} from "./purge.ts";

const OWNER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const OTHER = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const CUTOFF = "2026-10-09T00:00:00.000Z";
const EXPIRED = "2026-10-08T00:00:00.000Z";

function assert(ok: unknown, message: string): asserts ok {
  if (!ok) throw new Error(message);
}

function makeRows(count: number): ExpiredArtifact[] {
  return Array.from({ length: count }, (_, i) => {
    const id = `00000000-0000-4000-8000-${i.toString(16).padStart(12, "0")}`;
    return {
      id,
      owner_id: OWNER,
      storage_bucket: "recipe-import-artifacts",
      storage_path: `${OWNER}/${id}`,
      state: "available",
      expires_at: EXPIRED,
    };
  });
}

class FakePurgeSource implements ArtifactPurgeSource {
  readonly removed: string[] = [];
  readonly pages: number[] = [];
  readonly records: ExpiredArtifact[];
  readonly failPaths = new Set<string>();
  readonly failMarkIDs = new Set<string>();

  constructor(records: ExpiredArtifact[]) {
    this.records = records;
  }

  async listExpired(cutoff: string, offset: number, limit: number): Promise<ExpiredArtifact[]> {
    this.pages.push(offset);
    return this.records
      .filter((item) =>
        item.state !== "expired" && Date.parse(item.expires_at) <= Date.parse(cutoff)
      )
      .sort((a, b) =>
        a.expires_at.localeCompare(b.expires_at) || a.id.localeCompare(b.id)
      )
      .slice(offset, offset + limit)
      .map((item) => ({ ...item }));
  }

  async remove(path: string): Promise<void> {
    if (this.failPaths.has(path)) throw new Error("Fake Storage is unavailable");
    this.removed.push(path);
  }

  async markExpired(row: ExpiredArtifact, cutoff: string): Promise<boolean> {
    if (this.failMarkIDs.has(row.id)) return false;
    const current = this.records.find((item) => item.id === row.id);
    if (!current || current.state !== row.state ||
      current.expires_at !== row.expires_at ||
      Date.parse(current.expires_at) > Date.parse(cutoff)) return false;
    current.state = "expired";
    return true;
  }
}

Deno.test("cleanup processes 205 rows across stable pages without offset skips", async () => {
  const fake = new FakePurgeSource(makeRows(205));
  const report = await purgeExpiredArtifacts(fake, CUTOFF);
  assert(report.attempted === 205 && report.expired === 205, "Missing expired attachments");
  assert(report.failed === 0 && !report.has_more, "Unexpected partial cleanup");
  assert(fake.removed.length === 205, "Not all private objects were removed");
  assert(fake.pages.join(",") === "0,100,200", "Cursor skipped or duplicated a page");
});

Deno.test("Storage failure retains a retryable record", async () => {
  const fake = new FakePurgeSource(makeRows(2));
  fake.failPaths.add(fake.records[0].storage_path);
  const first = await purgeExpiredArtifacts(fake, CUTOFF);
  assert(first.expired === 1 && first.failed === 1, "Storage errors were hidden");
  assert(fake.records[0].state === "available", "Failed Storage object was marked expired");
  fake.failPaths.clear();
  const retried = await purgeExpiredArtifacts(fake, CUTOFF);
  assert(retried.expired === 1 && retried.failed === 0, "Retry failed to clear remaining object");
});

Deno.test("cleanup rejects cross-user paths and corrupted metadata without deleting", async () => {
  const rows = makeRows(3);
  rows[0].storage_path = `${OTHER}/${rows[0].id}`;
  rows[1].storage_bucket = "recipe-images";
  rows[2].expires_at = "not-a-date";
  const fake = new FakePurgeSource(rows);
  // The fake store filters out invalid dates like PostgreSQL would.
  const report = await purgeExpiredArtifacts(fake, CUTOFF);
  assert(report.failed === 2 && report.expired === 0, "Invalid rows were allowed");
  assert(fake.removed.length === 0, "A foreign or corrupted Storage path was removed");
});

Deno.test("one run is bounded, reports backlog, and the next run drains it", async () => {
  const fake = new FakePurgeSource(makeRows(ARTIFACT_CLEANUP_MAX_ROWS + 1));
  const first = await purgeExpiredArtifacts(fake, CUTOFF);
  assert(first.expired === ARTIFACT_CLEANUP_MAX_ROWS, "Bounded pass did not reach max rows");
  assert(first.has_more, "Remaining work was not signalled");
  const second = await purgeExpiredArtifacts(fake, CUTOFF);
  assert(second.expired === 1 && !second.has_more, "Remaining item could not be resumed");
  assert(ARTIFACT_CLEANUP_PAGE_SIZE === 100, "Page limit unexpectedly changed");
});

Deno.test("concurrent state update is reported rather than silently committed", async () => {
  const fake = new FakePurgeSource(makeRows(1));
  fake.failMarkIDs.add(fake.records[0].id);
  const report = await purgeExpiredArtifacts(fake, CUTOFF);
  assert(report.expired === 0 && report.failed === 1, "Lost CAS conflict was treated as success");
});

Deno.test("cleanup secret and timestamp validators fail closed", () => {
  assert(securelyEqual("Bearer valid-secret", "Bearer valid-secret"), "Valid token rejected");
  assert(!securelyEqual("Bearer valid-secret", "Bearer wrong-secret"), "Wrong secret accepted");
  assert(!securelyEqual("Bearer valid-secret", "Bearer valid-secret "), "Token suffix accepted");
  assert(!securelyEqual("x".repeat(513), "x".repeat(513)), "Oversized token accepted");
  const item = makeRows(1)[0];
  assert(isPurgeableArtifact(item, CUTOFF), "Valid owner-scoped object rejected");
  assert(!isPurgeableArtifact(item, "invalid"), "Invalid cutoff accepted");
  assert(!isPurgeableArtifact({ ...item, expires_at: "2099-01-01T00:00:00Z" }, CUTOFF),
    "Nonexpired object accepted");
  assert(!isPurgeableArtifact({ ...item, state: "expired" }, CUTOFF),
    "Already-expired object accepted for repeat deletion");
});
