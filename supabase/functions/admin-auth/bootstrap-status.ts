// Only expose whether an administrator has completed the bootstrap step.
export function bootstrapStatus(
  accounts: readonly { is_default_seed: boolean }[],
): { initialized: boolean } {
  return { initialized: accounts.some((account) => !account.is_default_seed) };
}
