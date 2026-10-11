import type { RevenueData } from "./types";

const isObject = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object";
const isAmount = (value: unknown) => value === null || (typeof value === "number" && Number.isFinite(value));
const isNumber = (value: unknown) => typeof value === "number" && Number.isFinite(value);

// Legacy totals lack currency evidence and must never be displayed as current financial data.
export function parseRevenue(value: unknown): RevenueData {
  if (!isObject(value) || !isObject(value.stats)) throw incompatibleRevenue();
  const stats = value.stats;
  if (
    !isAmount(stats.mrr) || !isAmount(stats.appleRevenue) || !isAmount(stats.androidRevenue) ||
    !(stats.currency === null || (typeof stats.currency === "string" && /^[A-Z]{3}$/.test(stats.currency))) ||
    !isNumber(stats.activePaid) || !isNumber(stats.incompleteEvents) || typeof stats.sourceRowsTruncated !== "boolean" ||
    !Array.isArray(stats.byCurrency) || !stats.byCurrency.every(row =>
      isObject(row) && typeof row.currency === "string" && /^[A-Z]{3}$/.test(row.currency) &&
      isNumber(row.appleRevenue) && isNumber(row.androidRevenue) && isNumber(row.total)) ||
    !Array.isArray(value.series) || !value.series.every(row =>
      isObject(row) && typeof row.month === "string" && isAmount(row.apple) && isAmount(row.android) && isAmount(row.total))
  ) throw incompatibleRevenue();
  return value as unknown as RevenueData;
}

function incompatibleRevenue() {
  return new Error("Revenue unavailable: the billing service needs an update.");
}
