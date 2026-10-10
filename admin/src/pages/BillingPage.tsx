import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import {
  Activity,
  Apple,
  ArrowDownToLine,
  BadgeCheck,
  CalendarDays,
  CircleAlert,
  CreditCard,
  LoaderCircle,
  Pencil,
  Plus,
  Search,
  Smartphone,
  Trash2,
  Users,
  WalletCards,
} from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { adminApi, handleExpiredSession } from "../api";
import { AdminSelect } from "../components/AdminSelect";
import type {
  AdminRole,
  RevenueData,
  SubscriptionPlan,
  SubscriptionRecord,
} from "../types";
import "./BillingPage.css";

type Platform = "all" | "app_store" | "play_store";
type Tab = "revenue" | "subscriptions" | "plans";

type BillingPageProps = {
  token: string;
  role: AdminRole;
  onAuthExpired: () => void;
};

type PlanDraft = Omit<SubscriptionPlan, "id" | "updatedAt">;

const emptyPlan: PlanDraft = {
  planKey: "pro",
  displayName: "Pro Monthly",
  platform: "app_store",
  productId: "",
  price: 0,
  currency: "USD",
  billingPeriod: "monthly",
  active: true,
  description: "",
};

function formatAmount(value: number | null | undefined, currency?: string | null) {
  if (value == null || !Number.isFinite(value)) return "—";
  if (currency) {
    try {
      return new Intl.NumberFormat(undefined, {
        style: "currency",
        currency,
        maximumFractionDigits: 2,
      }).format(value);
    } catch {
      return `${value.toFixed(2)} ${currency}`;
    }
  }
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value);
}

function formatDate(value: string | null | undefined) {
  if (!value) return "No expiry";
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? value
    : new Intl.DateTimeFormat(undefined, { year: "numeric", month: "short", day: "numeric" }).format(parsed);
}

function platformLabel(platform: Platform | SubscriptionPlan["platform"] | null) {
  if (platform === "app_store") return "App Store";
  if (platform === "play_store") return "Google Play";
  return "All platforms";
}

function planStatus(status: string) {
  const normalized = status.toLowerCase();
  if (["active", "trialing"].includes(normalized)) return "positive";
  if (["expired", "cancelled", "canceled", "none"].includes(normalized)) return "muted";
  return "warning";
}

function ErrorNotice({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="billing-error" role="alert">
      <CircleAlert size={18} aria-hidden="true" />
      <span>{message}</span>
      <button className="billing-text-button" type="button" onClick={onRetry}>Try again</button>
    </div>
  );
}

function LoadingState() {
  return (
    <div className="billing-loading" role="status">
      <LoaderCircle size={20} className="billing-spin" aria-hidden="true" />
      <span>Loading billing data…</span>
    </div>
  );
}

function StatCard({
  label,
  value,
  detail,
  icon: Icon,
}: {
  label: string;
  value: string;
  detail: string;
  icon: typeof CreditCard;
}) {
  return (
    <article className="billing-stat-card">
      <div className="billing-stat-top">
        <span>{label}</span>
        <span className="billing-stat-icon"><Icon size={17} aria-hidden="true" /></span>
      </div>
      <strong>{value}</strong>
      <small>{detail}</small>
    </article>
  );
}

function mergeRevenue(first: RevenueData, second: RevenueData): RevenueData {
  const byMonth = new Map<string, RevenueData["series"][number]>();
  for (const row of first.series) {
    byMonth.set(row.month, { month: row.month, apple: row.apple, android: 0, total: row.apple });
  }
  for (const row of second.series) {
    const previous = byMonth.get(row.month) ?? { month: row.month, apple: 0, android: 0, total: 0 };
    previous.android = row.android;
    previous.total = previous.apple + previous.android;
    byMonth.set(row.month, previous);
  }
  return {
    stats: {
      // Never combine unavailable recurring revenue estimates from catalog prices.
      mrr: null,
      appleRevenue: first.stats.appleRevenue,
      androidRevenue: second.stats.androidRevenue,
      activePaid: Math.max(first.stats.activePaid, second.stats.activePaid),
    },
    series: [...byMonth.values()],
  };
}

export default function BillingPage({ token, role, onAuthExpired }: BillingPageProps) {
  const canManagePlans = role === "owner" || role === "admin";
  const canReadFinancials = canManagePlans;
  const [tab, setTab] = useState<Tab>(canReadFinancials ? "revenue" : "plans");
  const [platform, setPlatform] = useState<Platform>("all");
  const [records, setRecords] = useState<SubscriptionRecord[]>([]);
  const [revenue, setRevenue] = useState<RevenueData | null>(null);
  const [plans, setPlans] = useState<SubscriptionPlan[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [planEditor, setPlanEditor] = useState<SubscriptionPlan | "new" | null>(null);
  const [planDraft, setPlanDraft] = useState<PlanDraft>(emptyPlan);
  const [savingPlan, setSavingPlan] = useState(false);
  const [planError, setPlanError] = useState("");
  const loadId = useRef(0);

  const load = async () => {
    const currentLoadId = ++loadId.current;
    setLoading(true);
    setError("");
    try {
      const platformFilter = platform === "all" ? undefined : platform;
      if (tab === "plans") {
        const nextPlans = await adminApi.plans(token);
        if (loadId.current === currentLoadId) setPlans(nextPlans);
      } else if (!canReadFinancials) {
        if (loadId.current === currentLoadId) setError("Billing records and revenue are available to owners and admins.");
      } else if (tab === "subscriptions") {
        const nextRecords = await adminApi.records(token, platformFilter);
        if (loadId.current === currentLoadId) setRecords(nextRecords);
      } else if (platform === "all") {
        const [apple, android] = await Promise.all([
          adminApi.revenue(token, "app_store"),
          adminApi.revenue(token, "play_store"),
        ]);
        if (loadId.current === currentLoadId) setRevenue(mergeRevenue(apple, android));
      } else {
        const nextRevenue = await adminApi.revenue(token, platform);
        if (loadId.current === currentLoadId) setRevenue(nextRevenue);
      }
    } catch (cause) {
      if (loadId.current !== currentLoadId) return;
      handleExpiredSession(cause, onAuthExpired);
      setError(cause instanceof Error ? cause.message : "Unable to load billing data.");
    } finally {
      if (loadId.current === currentLoadId) setLoading(false);
    }
  };

  useEffect(() => {
    if (!canReadFinancials && tab !== "plans") {
      setTab("plans");
      return;
    }
    void load();
    return () => { loadId.current += 1; };
    // Reload only for the selected resource, platform, session or role.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, tab, platform, role]);

  const visibleRecords = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase();
    if (!normalized) return records;
    return records.filter((record) =>
      [record.user.displayName, record.user.email, record.plan, record.productId, record.status]
        .some((field) => field?.toLocaleLowerCase().includes(normalized)),
    );
  }, [query, records]);

  const visiblePlans = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase();
    return plans.filter((plan) => {
      const matchesPlatform = platform === "all" || plan.platform === platform;
      const matchesQuery = !normalized || [plan.displayName, plan.planKey, plan.productId, plan.description]
        .some((field) => field?.toLocaleLowerCase().includes(normalized));
      return matchesPlatform && matchesQuery;
    });
  }, [plans, platform, query]);

  function beginCreatePlan() {
    setPlanDraft({ ...emptyPlan });
    setPlanError("");
    setPlanEditor("new");
  }

  function beginEditPlan(plan: SubscriptionPlan) {
    setPlanDraft({
      planKey: plan.planKey,
      displayName: plan.displayName,
      platform: plan.platform,
      productId: plan.productId,
      price: plan.price,
      currency: plan.currency,
      billingPeriod: plan.billingPeriod,
      active: plan.active,
      description: plan.description ?? "",
    });
    setPlanError("");
    setPlanEditor(plan);
  }

  async function savePlan(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSavingPlan(true);
    setPlanError("");
    try {
      const saved = await adminApi.savePlan(token, {
        ...planDraft,
        description: planDraft.description?.trim() || null,
      }, planEditor !== "new" && planEditor ? planEditor.id : undefined);
      setPlans((current) => {
        const exists = current.some((plan) => plan.id === saved.id);
        return exists ? current.map((plan) => plan.id === saved.id ? saved : plan) : [...current, saved];
      });
      setPlanEditor(null);
    } catch (cause) {
      handleExpiredSession(cause, onAuthExpired);
      setPlanError(cause instanceof Error ? cause.message : "Unable to save this plan.");
    } finally {
      setSavingPlan(false);
    }
  }

  async function deletePlan(plan: SubscriptionPlan) {
    const confirmed = window.confirm(`Delete “${plan.displayName}” (${plan.productId})? This action cannot be undone.`);
    if (!confirmed) return;
    setError("");
    try {
      await adminApi.deletePlan(token, plan.id);
      setPlans((current) => current.filter((item) => item.id !== plan.id));
    } catch (cause) {
      handleExpiredSession(cause, onAuthExpired);
      setError(cause instanceof Error ? cause.message : "Unable to delete this plan.");
    }
  }

  const title = tab === "revenue" ? "Revenue" : tab === "subscriptions" ? "Subscriptions" : "Plans & products";

  return (
    <main className="billing-page">
      <header className="billing-header">
        <div>
          <div className="billing-eyebrow"><WalletCards size={15} aria-hidden="true" /> FINANCE</div>
          <h1>Billing</h1>
          <p>Monitor subscription activity and manage store products.</p>
        </div>
        <div className="billing-header-actions">
          <AdminSelect
            className="billing-platform-select"
            label="Platform"
            value={platform}
            onValueChange={(value) => setPlatform(value as Platform)}
            options={[
              { value: "all", label: "All platforms" },
              { value: "app_store", label: "App Store" },
              { value: "play_store", label: "Google Play" },
            ]}
          />
          {tab === "plans" && canManagePlans && (
            <button className="billing-primary-button" type="button" onClick={beginCreatePlan}>
              <Plus size={17} aria-hidden="true" /> Add plan
            </button>
          )}
        </div>
      </header>

      <nav className="billing-tabs" aria-label="Billing sections">
        {canReadFinancials && (
          <>
            <button className={tab === "revenue" ? "active" : ""} type="button" onClick={() => { setTab("revenue"); setQuery(""); }}>
              <Activity size={16} aria-hidden="true" /> Revenue
            </button>
            <button className={tab === "subscriptions" ? "active" : ""} type="button" onClick={() => { setTab("subscriptions"); setQuery(""); }}>
              <CreditCard size={16} aria-hidden="true" /> Subscriptions
            </button>
          </>
        )}
        <button className={tab === "plans" ? "active" : ""} type="button" onClick={() => { setTab("plans"); setQuery(""); }}>
          <BadgeCheck size={16} aria-hidden="true" /> Plans & products
        </button>
      </nav>

      <section className="billing-content" aria-labelledby="billing-section-title">
        <div className="billing-section-heading">
          <div>
            <h2 id="billing-section-title">{title}</h2>
            <p>{tab === "revenue" ? "Sales captured from App Store and Google Play purchase events." : tab === "subscriptions" ? "Current subscription records returned by the billing service." : "Store product catalog and subscription pricing."}</p>
          </div>
          {(tab === "subscriptions" || tab === "plans") && (
            <label className="billing-search">
              <Search size={16} aria-hidden="true" />
              <input type="search" aria-label={tab === "plans" ? "Search plans" : "Search subscribers"} value={query} onChange={(event) => setQuery(event.target.value)} placeholder={tab === "plans" ? "Search plans…" : "Search subscribers…"} />
            </label>
          )}
        </div>

        {error && <ErrorNotice message={error} onRetry={() => void load()} />}
        {loading ? <LoadingState /> : !error && tab === "revenue" && revenue && (
          <>
            <div className="billing-stat-grid">
              <StatCard label="Monthly recurring revenue" value={formatAmount(revenue.stats.mrr)} detail="Requires verified subscriber-level recurring amounts" icon={WalletCards} />
              <StatCard label="App Store revenue" value={formatAmount(revenue.stats.appleRevenue)} detail="Recorded purchase events" icon={Apple} />
              <StatCard label="Google Play revenue" value={formatAmount(revenue.stats.androidRevenue)} detail="Recorded purchase events" icon={Smartphone} />
              <StatCard label="Active paid subscribers" value={new Intl.NumberFormat().format(revenue.stats.activePaid)} detail="Active or trialing plans" icon={Users} />
            </div>
            <section className="billing-panel billing-chart-panel">
              <div className="billing-panel-heading">
                <div><h3>Revenue over time</h3><p>Monthly sales by app store</p></div>
                <span className="billing-period-label"><CalendarDays size={15} aria-hidden="true" /> Last 6 months</span>
              </div>
              {revenue.series.length === 0 ? (
                <div className="billing-empty"><ArrowDownToLine size={22} aria-hidden="true" /><strong>No purchase events yet</strong><span>Revenue appears here after the billing service records store purchases.</span></div>
              ) : (
                <div className="billing-chart">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={revenue.series} margin={{ top: 12, right: 8, left: 0, bottom: 2 }} barGap={5}>
                      <CartesianGrid vertical={false} stroke="var(--billing-border)" strokeDasharray="3 5" />
                      <XAxis dataKey="month" axisLine={false} tickLine={false} tick={{ fill: "var(--billing-muted)", fontSize: 12 }} dy={8} />
                      <YAxis axisLine={false} tickLine={false} tick={{ fill: "var(--billing-muted)", fontSize: 12 }} tickFormatter={(value: number) => new Intl.NumberFormat(undefined, { notation: "compact" }).format(value)} width={45} />
                      <Tooltip formatter={(value) => [formatAmount(Number(value)), ""]} cursor={{ fill: "var(--billing-hover)" }} contentStyle={{ borderRadius: 10, borderColor: "var(--billing-border)", boxShadow: "0 8px 24px rgba(22, 26, 36, .08)" }} />
                      <Bar dataKey="apple" name="App Store" fill="var(--billing-apple)" radius={[4, 4, 0, 0]} maxBarSize={28} />
                      <Bar dataKey="android" name="Google Play" fill="var(--billing-android)" radius={[4, 4, 0, 0]} maxBarSize={28} />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              )}
              <div className="billing-chart-legend"><span><i className="apple-dot" /> App Store</span><span><i className="android-dot" /> Google Play</span></div>
            </section>
          </>
        )}

        {!loading && !error && tab === "subscriptions" && (
          <section className="billing-panel">
            <div className="billing-table-wrap">
              <table className="billing-table">
                <thead><tr><th>Subscriber</th><th>Plan</th><th>Status</th><th>Platform</th><th>Product ID</th><th>Amount</th><th>Expires</th></tr></thead>
                <tbody>
                  {visibleRecords.map((record) => (
                    <tr key={`${record.id}-${record.platform ?? "unknown"}`}>
                      <td><div className="billing-person"><span className="billing-avatar">{(record.user.displayName || record.user.email || "?").slice(0, 1).toUpperCase()}</span><span><strong>{record.user.displayName || "Unknown user"}</strong><small>{record.user.email || record.user.id}</small></span></div></td>
                      <td><span className="billing-plan-name">{record.plan}</span></td>
                      <td><span className={`billing-status ${planStatus(record.status)}`}><i />{record.status}</span></td>
                      <td>{platformLabel(record.platform)}</td>
                      <td className="billing-mono">{record.productId || "—"}</td>
                      <td>{formatAmount(record.amount, record.currency)}</td>
                      <td>{formatDate(record.expirationDate)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {visibleRecords.length === 0 && <div className="billing-table-empty">{records.length === 0 ? "No subscription records have been returned." : "No subscription records match this view."}</div>}
            </div>
            <div className="billing-table-footer">Showing {visibleRecords.length} subscription{visibleRecords.length === 1 ? "" : "s"} returned by the service</div>
          </section>
        )}

        {!loading && !error && tab === "plans" && (
          <section className="billing-panel">
            <div className="billing-table-wrap">
              <table className="billing-table billing-plans-table">
                <thead><tr><th>Plan</th><th>Platform</th><th>Product ID</th><th>Price</th><th>Billing period</th><th>Status</th>{canManagePlans && <th><span className="billing-sr-only">Actions</span></th>}</tr></thead>
                <tbody>
                  {visiblePlans.map((plan) => (
                    <tr key={plan.id}>
                      <td><div className="billing-plan-cell"><span className="billing-plan-glyph"><CreditCard size={17} aria-hidden="true" /></span><span><strong>{plan.displayName}</strong><small>{plan.planKey}{plan.description ? ` · ${plan.description}` : ""}</small></span></div></td>
                      <td><span className={`billing-store-pill ${plan.platform}`}><i />{platformLabel(plan.platform)}</span></td>
                      <td className="billing-mono">{plan.productId}</td>
                      <td><strong>{formatAmount(plan.price, plan.currency)}</strong></td>
                      <td className="billing-capitalize">{plan.billingPeriod}</td>
                      <td><span className={`billing-status ${plan.active ? "positive" : "muted"}`}><i />{plan.active ? "Active" : "Inactive"}</span></td>
                      {canManagePlans && <td><div className="billing-row-actions"><button type="button" aria-label={`Edit ${plan.displayName}`} title="Edit plan" onClick={() => beginEditPlan(plan)}><Pencil size={15} aria-hidden="true" /></button><button type="button" className="danger" aria-label={`Delete ${plan.displayName}`} title="Delete plan" onClick={() => void deletePlan(plan)}><Trash2 size={15} aria-hidden="true" /></button></div></td>}
                    </tr>
                  ))}
                </tbody>
              </table>
              {visiblePlans.length === 0 && <div className="billing-table-empty">{plans.length === 0 ? "No subscription plans are configured yet." : "No plans match this view."}</div>}
            </div>
            <div className="billing-table-footer">{visiblePlans.length} plan{visiblePlans.length === 1 ? "" : "s"}{!canManagePlans && <span> · Read-only access</span>}</div>
          </section>
        )}
      </section>

      {planEditor && (
        <div className="billing-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !savingPlan) setPlanEditor(null); }}>
          <section className="billing-dialog" role="dialog" aria-modal="true" aria-labelledby="plan-dialog-title">
            <header><div><span className="billing-dialog-icon"><CreditCard size={18} aria-hidden="true" /></span><h2 id="plan-dialog-title">{planEditor === "new" ? "Add a plan" : "Edit plan"}</h2></div><button type="button" className="billing-dialog-close" aria-label="Close dialog" onClick={() => setPlanEditor(null)}>×</button></header>
            <p className="billing-dialog-copy">Set the product identifier and price used by the selected store.</p>
            <form onSubmit={(event) => void savePlan(event)}>
              <div className="billing-form-grid">
                <label className="billing-field"><span>Display name</span><input required value={planDraft.displayName} onChange={(event) => setPlanDraft({ ...planDraft, displayName: event.target.value })} /></label>
                <label className="billing-field"><span>Plan key</span><input required value={planDraft.planKey} onChange={(event) => setPlanDraft({ ...planDraft, planKey: event.target.value })} /></label>
                <AdminSelect
                  className="billing-field-select"
                  label="Platform"
                  value={planDraft.platform}
                  onValueChange={(value) => setPlanDraft({ ...planDraft, platform: value as SubscriptionPlan["platform"] })}
                  options={[
                    { value: "app_store", label: "App Store" },
                    { value: "play_store", label: "Google Play" },
                  ]}
                />
                <AdminSelect
                  className="billing-field-select"
                  label="Billing period"
                  value={planDraft.billingPeriod}
                  onValueChange={(value) => setPlanDraft({ ...planDraft, billingPeriod: value as PlanDraft["billingPeriod"] })}
                  options={[
                    { value: "monthly", label: "Monthly" },
                    { value: "yearly", label: "Yearly" },
                    { value: "lifetime", label: "Lifetime" },
                  ]}
                />
                <label className="billing-field billing-field-wide"><span>Store product ID</span><input required value={planDraft.productId} onChange={(event) => setPlanDraft({ ...planDraft, productId: event.target.value })} /></label>
                <label className="billing-field"><span>Price</span><input type="number" min="0" step="0.01" required value={planDraft.price} onChange={(event) => setPlanDraft({ ...planDraft, price: Number(event.target.value) })} /></label>
                <label className="billing-field"><span>Currency</span><input required maxLength={3} value={planDraft.currency} onChange={(event) => setPlanDraft({ ...planDraft, currency: event.target.value.toUpperCase() })} /></label>
                <label className="billing-field billing-field-wide"><span>Description <small>Optional</small></span><input value={planDraft.description ?? ""} onChange={(event) => setPlanDraft({ ...planDraft, description: event.target.value })} /></label>
              </div>
              <label className="billing-toggle"><input type="checkbox" checked={planDraft.active} onChange={(event) => setPlanDraft({ ...planDraft, active: event.target.checked })} /><span><strong>Available for purchase</strong><small>Active products can be offered in the app.</small></span></label>
              {planError && <div className="billing-form-error" role="alert">{planError}</div>}
              <footer><button type="button" className="billing-secondary-button" disabled={savingPlan} onClick={() => setPlanEditor(null)}>Cancel</button><button type="submit" className="billing-primary-button" disabled={savingPlan}>{savingPlan && <LoaderCircle size={15} className="billing-spin" aria-hidden="true" />}{savingPlan ? "Saving…" : "Save plan"}</button></footer>
            </form>
          </section>
        </div>
      )}
    </main>
  );
}
