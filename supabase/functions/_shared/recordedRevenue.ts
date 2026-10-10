// Developer: gengyun
// Purpose: Group recorded purchase amounts by declared currency; never invent FX conversion.

/**
 * A product change is a change of entitlement; RevenueCat may also emit a
 * separate RENEWAL or INITIAL_PURCHASE for the same immediate upgrade.
 * Do not count PRODUCT_CHANGE as an additional purchase event.
 * https://www.revenuecat.com/docs/integrations/webhooks/event-flows
 */
export function isRecordedPurchaseEvent(eventType: unknown): boolean {
  const value = typeof eventType === "string" ? eventType.toUpperCase() : "";
  return value === "INITIAL_PURCHASE" || value === "RENEWAL" ||
    value === "NON_RENEWING_PURCHASE";
}

export type RevenueStore = "app_store" | "play_store";
export type RevenueCurrencyRow = {
  currency: string;
  appleRevenue: number;
  androidRevenue: number;
  total: number;
};

type RunningTotals = { apple: number; android: number };
export type RecordedRevenueSummary = {
  currency: string | null;
  comparable: boolean;
  incompleteEvents: number;
  sourceRowsTruncated: boolean;
  appleRevenue: number | null;
  androidRevenue: number | null;
  total: number | null;
  byCurrency: RevenueCurrencyRow[];
};

const round2 = (value: number): number => Math.round(value * 100) / 100;

function currencyCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const currency = value.trim().toUpperCase();
  return /^[A-Z]{3}$/.test(currency) ? currency : null;
}

/** Figures are recorded event amounts, not reconciled settled or net revenue. */
export class RecordedRevenueLedger {
  private readonly groups = new Map<string, RunningTotals>();
  private readonly months = new Map<string, Map<string, RunningTotals>>();
  private missing = 0;

  record(raw: unknown, store: unknown, month: string): void {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      this.missing++;
      return;
    }
    const event = raw as Record<string, unknown>;
    const rawAmount = event.price_in_purchased_currency ?? event.price;
    if (rawAmount === null || rawAmount === undefined || rawAmount === "") {
      this.missing++;
      return;
    }
    const amount = typeof rawAmount === "number" || typeof rawAmount === "string"
      ? Number(rawAmount)
      : NaN;
    if (!Number.isFinite(amount) || amount < 0) {
      this.missing++;
      return;
    }
    if (amount === 0) return;
    const currency = currencyCode(event.currency ?? event.currency_code);
    if (!currency || (store !== "app_store" && store !== "play_store") ||
      !/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) {
      this.missing++;
      return;
    }
    const totals = this.groups.get(currency) ?? { apple: 0, android: 0 };
    const monthGroups = this.months.get(month) ?? new Map<string, RunningTotals>();
    const monthTotals = monthGroups.get(currency) ?? { apple: 0, android: 0 };
    const next = {
      apple: totals.apple + (store === "app_store" ? amount : 0),
      android: totals.android + (store === "play_store" ? amount : 0),
    };
    const nextMonth = {
      apple: monthTotals.apple + (store === "app_store" ? amount : 0),
      android: monthTotals.android + (store === "play_store" ? amount : 0),
    };
    if (![next.apple, next.android, nextMonth.apple, nextMonth.android]
      .every(Number.isFinite)) {
      this.missing++;
      return;
    }
    this.groups.set(currency, next);
    monthGroups.set(currency, nextMonth);
    this.months.set(month, monthGroups);
  }

  monthKeys(): string[] {
    return [...this.months.keys()];
  }

  monthly(month: string, currency: string | null): RunningTotals | null {
    if (!currency) return null;
    const data = this.months.get(month)?.get(currency);
    return data ? { apple: round2(data.apple), android: round2(data.android) }
      : { apple: 0, android: 0 };
  }

  summary(sourceRowsTruncated = false): RecordedRevenueSummary {
    const byCurrency = [...this.groups.entries()].sort((a, b) => a[0].localeCompare(b[0]))
      .map(([currency, totals]) => ({
        currency,
        appleRevenue: round2(totals.apple),
        androidRevenue: round2(totals.android),
        total: round2(totals.apple + totals.android),
      }));
    const comparable = !sourceRowsTruncated && this.missing === 0 &&
      byCurrency.length === 1;
    const row = comparable ? byCurrency[0] : null;
    return {
      currency: row?.currency ?? null,
      comparable,
      incompleteEvents: this.missing,
      sourceRowsTruncated,
      appleRevenue: row?.appleRevenue ?? null,
      androidRevenue: row?.androidRevenue ?? null,
      total: row?.total ?? null,
      byCurrency,
    };
  }
}
