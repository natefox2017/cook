// Developer: gengyun
// Purpose: Keep financial and growth aggregates separated by UTC calendar year and month.

/** A grouping key is always YYYY-MM, never a localized month name. */
export function utcMonthKey(value: string): string {
  const source = value.trim();
  const monthOnly = /^\d{4}-(?:0[1-9]|1[0-2])$/.test(source);
  const dateOnly = /^\d{4}-(?:0[1-9]|1[0-2])-\d{2}$/.test(source);
  const timestamp = /^\d{4}-(?:0[1-9]|1[0-2])-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/i.test(source);
  if (!monthOnly && !dateOnly && !timestamp) {
    throw new Error("Invalid report month");
  }
  const date = new Date(monthOnly ? source + "-01T00:00:00Z" : source);
  if (!Number.isFinite(date.getTime())) throw new Error("Invalid report month");
  return String(date.getUTCFullYear()).padStart(4, "0") + "-" +
    String(date.getUTCMonth() + 1).padStart(2, "0");
}

/** Human-facing recent-activity text, separate from the stable group identity. */
export function displayUTCMonth(value: string): string {
  const month = utcMonthKey(value);
  const [year, number] = month.split("-").map(Number);
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  }).format(new Date(Date.UTC(year, number - 1, 1)));
}
