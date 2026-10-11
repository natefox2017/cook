export function isSecureApiEndpoint(base: string | undefined, origin: string): boolean {
  if (!base) return false;
  try {
    const url = new URL(base, origin);
    return url.protocol === "https:" && !url.username && !url.password && !url.search && !url.hash;
  } catch {
    return false;
  }
}
