// Developer: gengyun
// Purpose: Reject reports that silently omit rows at a query or server page limit.

/**
 * Supabase/PostgREST can apply a lower configured maxRows than the requested
 * limit. With an exact total we can reject that too, rather than treat missing
 * rows as zero. No partial report is ever labeled complete.
 */
export function hasCompletePage(
  rows: readonly unknown[] | null | undefined,
  requestedLimit: number,
  exactCount: number | null | undefined = null,
): boolean {
  if (!Array.isArray(rows) || !Number.isSafeInteger(requestedLimit) ||
    requestedLimit < 1 || rows.length >= requestedLimit) {
    return false;
  }
  if (exactCount !== null && exactCount !== undefined &&
    (!Number.isSafeInteger(exactCount) || exactCount < 0 ||
      exactCount > rows.length)) {
    return false;
  }
  return true;
}
