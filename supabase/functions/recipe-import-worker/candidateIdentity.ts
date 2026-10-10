// Developer: gengyun
// Purpose: Generate order-independent candidate IDs without using mutable page position.

export interface CandidateIdentityEvidence {
  title: string | null;
  ingredients: readonly string[];
  steps: readonly string[];
}

const FNV_OFFSET = 0xcbf29ce484222325n;
const FNV_PRIME = 0x100000001b3n;
const UINT64_MASK = 0xffffffffffffffffn;

/**
 * Fingerprint supplied structured recipe facts, never evidence UUIDs, time or
 * the location of a dish within a page. This is a dedupe hint, not an auth key.
 */
function contentFingerprint(candidate: CandidateIdentityEvidence): string {
  const basis = JSON.stringify([
    candidate.title,
    candidate.ingredients,
    candidate.steps,
  ]).normalize("NFC");
  let forward = FNV_OFFSET;
  let backward = FNV_OFFSET ^ UINT64_MASK;
  const bytes = new TextEncoder().encode(basis);
  for (const byte of bytes) {
    forward = (forward ^ BigInt(byte)) * FNV_PRIME & UINT64_MASK;
  }
  for (let index = bytes.length - 1; index >= 0; index--) {
    backward = (backward ^ BigInt(bytes[index])) * FNV_PRIME & UINT64_MASK;
  }
  return forward.toString(16).padStart(16, "0") +
    backward.toString(16).padStart(16, "0");
}

/**
 * Old candidate-<index>-<hash> IDs remain intact in historical saved receipts.
 * New v2 IDs survive reordering and insertion of unrelated JSON-LD recipes.
 * Identical duplicate nodes receive deterministic occurrence suffixes.
 */
export function stableCandidateIDs(
  candidates: readonly CandidateIdentityEvidence[],
): string[] {
  const seen = new Map<string, number>();
  return candidates.map((candidate) => {
    const fingerprint = contentFingerprint(candidate);
    const occurrence = (seen.get(fingerprint) ?? 0) + 1;
    seen.set(fingerprint, occurrence);
    return "candidate-v2-" + fingerprint + (occurrence > 1 ? "-" + occurrence : "");
  });
}
