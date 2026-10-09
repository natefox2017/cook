// Developer: RecipePouch
// Purpose: Bounded non-short-circuit comparison of high-entropy server bearer tokens.

export function securelyEqualTokens(left: string, right: string): boolean {
  // Never buffer arbitrarily long untrusted Authorization headers.
  if (left.length > 512 || right.length > 512) return false;
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let difference = a.length ^ b.length;
  for (let index = 0; index < Math.max(a.length, b.length); index++) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}
