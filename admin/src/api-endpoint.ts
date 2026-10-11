export function isSecureApiEndpoint(base: string | undefined, origin: string): boolean {
  if (!base) return false;
  try {
    return new URL(base, origin).protocol === "https:";
  } catch {
    return false;
  }
}
