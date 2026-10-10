import { useCallback, useEffect, useState, type FormEvent } from "react";
import {
  Activity,
  ArrowUpRight,
  CircleDollarSign,
  RefreshCw,
  ShieldCheck,
  Users,
} from "lucide-react";
import {
  Area,
  AreaChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { adminApi, handleExpiredSession, isConfigured } from "./api";
import type { AdminSession, DashboardData } from "./types";
import UsersPage from "./pages/UsersPage";
import BillingPage from "./pages/BillingPage";
import { LLMPage } from "./pages/LLMPage";
import { AdminSecurityPage } from "./security/AdminSecurityPage";
import { AdminLogin } from "./pages/AdminLogin";
import AdminShell, { type AdminPage } from "./components/AdminShell";
import "./App.css";

const sessionStorageKey = "recipe.admin.session";
const chartColors = ["#16a34a", "#86efac", "#d1d5db"];
const routePaths: Record<AdminPage, string> = {
  overview: "/admin",
  users: "/admin/users",
  billing: "/admin/subscriptions",
  llm: "/admin/ai-models",
  security: "/admin/security",
};

function readStoredSession(): AdminSession | null {
  try {
    const raw = sessionStorage.getItem(sessionStorageKey);
    if (!raw) return null;

    const saved = JSON.parse(raw) as AdminSession;
    if (!saved.token || !saved.expiresAt || !saved.admin || Date.parse(saved.expiresAt) <= Date.now()) {
      sessionStorage.removeItem(sessionStorageKey);
      return null;
    }
    return saved;
  } catch {
    sessionStorage.removeItem(sessionStorageKey);
    return null;
  }
}

function pageFromPath(pathname: string): AdminPage | null {
  return (Object.entries(routePaths) as Array<[AdminPage, string]>)
    .find(([, path]) => path === pathname)?.[0] ?? null;
}

function defaultPage(role: AdminSession["admin"]["role"]): AdminPage {
  return role === "owner" ? "overview" : role === "admin" ? "users" : "billing";
}

function canOpenPage(role: AdminSession["admin"]["role"], page: AdminPage) {
  if (page === "overview") return role === "owner";
  if (page === "users" || page === "llm") return role === "owner" || role === "admin";
  return true;
}

function formatNumber(value: number) {
  return new Intl.NumberFormat("en-US", { notation: value > 9999 ? "compact" : "standard" }).format(value);
}

function formatMoney(value: number | null, currency: string | null) {
  if (value == null || !Number.isFinite(value) || !currency) return "—";
  try {
    return new Intl.NumberFormat("en-US", {
      style: "currency", currency, maximumFractionDigits: 2,
    }).format(value);
  } catch {
    return `${value.toFixed(2)} ${currency}`;
  }
}

function ChangePassword({ session, onUpdated }: { session: AdminSession; onUpdated: (next: AdminSession) => void }) {
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    if (newPassword !== confirmation) {
      setError("The new passwords do not match.");
      return;
    }
    setSaving(true);
    try {
      const next = await adminApi.changePassword(session.token, currentPassword, newPassword);
      onUpdated(next);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Password change failed.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-backdrop">
      <section className="modal-card card" role="dialog" aria-modal="true" aria-labelledby="password-title">
        <div className="modal-icon"><ShieldCheck size={21} /></div>
        <p className="eyebrow">ACCOUNT SECURITY</p>
        <h2 id="password-title">Change your password</h2>
        <p className="muted">Choose a new password before opening the admin dashboard.</p>
        <form className="login-form" onSubmit={submit}>
          <label htmlFor="current-password">Current password</label>
          <input id="current-password" type="password" autoComplete="current-password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} required />
          <label htmlFor="new-password">New password</label>
          <input id="new-password" type="password" autoComplete="new-password" value={newPassword} onChange={(event) => setNewPassword(event.target.value)} minLength={12} required />
          <label htmlFor="confirm-password">Confirm new password</label>
          <input id="confirm-password" type="password" autoComplete="new-password" value={confirmation} onChange={(event) => setConfirmation(event.target.value)} required />
          {error && <p className="form-error" role="alert">{error}</p>}
          <button className="button button-primary login-submit" disabled={saving}>{saving ? "Updating…" : "Update password"}</button>
        </form>
      </section>
    </div>
  );
}

function MetricCard({ label, value, note, icon: Icon, tone = "green" }: { label: string; value: string; note: string; icon: typeof Users; tone?: string }) {
  return (
    <article className="card metric-card">
      <div className="metric-top"><span>{label}</span><span className={`metric-icon ${tone}`}><Icon size={17} /></span></div>
      <div className="metric-value">{value}</div>
      <div className="metric-note">{note}</div>
    </article>
  );
}

function EmptyChart({ label }: { label: string }) {
  return <div className="chart-empty"><span className="chart-empty-mark"><Activity size={19} /></span><strong>No data yet</strong><span>{label}</span></div>;
}

function Overview({ token, onAuthExpired }: { token: string; onAuthExpired: () => void }) {
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const refresh = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      setData(await adminApi.dashboard(token));
    } catch (cause) {
      handleExpiredSession(cause, onAuthExpired);
      setError(cause instanceof Error ? cause.message : "Unable to load dashboard data.");
    } finally {
      setLoading(false);
    }
  }, [token, onAuthExpired]);

  useEffect(() => { void refresh(); }, [refresh]);

  if (loading && !data) return <div className="loading-panel"><span className="spinner" /> Loading dashboard…</div>;
  if (error && !data) return <div className="card error-panel"><h2>Dashboard unavailable</h2><p>{error}</p><button className="button button-outline" onClick={() => void refresh()}><RefreshCw size={15} /> Try again</button></div>;
  if (!data) return null;

  const planRows = data.userBreakdown.byPlan.filter((item) => item.value > 0);
  return (
    <div className="page-content">
        <div className="page-heading-row">
        <div><p className="eyebrow">OPERATIONS</p><h1>Overview</h1><p className="muted">Registration, subscriptions and revenue at a glance.</p></div>
        <button className="button button-outline" onClick={() => void refresh()} disabled={loading}><RefreshCw size={15} className={loading ? "spin" : ""} /> Refresh</button>
      </div>
      {error && <div className="notice notice-warning">Some data could not be refreshed: {error}</div>}
      <section className="metric-grid">
        <MetricCard label="Total users" value={formatNumber(data.stats.totalUsers)} note={`+${formatNumber(data.stats.newUsersThisMonth)} this month`} icon={Users} />
        <MetricCard label="Registrations this month" value={formatNumber(data.stats.newUsersThisMonth)} note="New app users" icon={ArrowUpRight} tone="blue" />
        <MetricCard label="Active paid" value={formatNumber(data.stats.activePaidUsers)} note={`${formatNumber(data.stats.suspendedUsers)} suspended accounts`} icon={ArrowUpRight} tone="amber" />
        <MetricCard
          label="Recorded purchases"
          value={formatMoney(data.stats.revenueTotal, data.stats.revenueCurrency)}
          note={data.stats.revenueRowsTruncated || data.stats.incompleteRevenueEvents > 0
            ? "Incomplete purchase data — totals unavailable"
            : !data.stats.revenueCurrency ? "Mixed/unknown currencies — see Billing" : "Unreconciled recorded purchase amounts"}
          icon={CircleDollarSign}
          tone="violet"
        />
      </section>

      <section className="overview-grid">
        <article className="card chart-card">
          <div className="card-heading"><div><h2>Registered users</h2><p className="muted">Cumulative registrations · last 6 months</p></div><span className="legend"><i className="legend-green" /> Users</span></div>
          {data.growth.length ? <div className="chart-area"><ResponsiveContainer width="100%" height="100%"><AreaChart data={data.growth} margin={{ top: 10, right: 8, left: -18, bottom: 0 }}><defs><linearGradient id="usersFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#16a34a" stopOpacity={0.18} /><stop offset="100%" stopColor="#16a34a" stopOpacity={0} /></linearGradient></defs><CartesianGrid stroke="#e8ece8" vertical={false} /><XAxis dataKey="month" axisLine={false} tickLine={false} tick={{ fill: "#8b948e", fontSize: 11 }} dy={9} /><YAxis axisLine={false} tickLine={false} tick={{ fill: "#8b948e", fontSize: 11 }} /><Tooltip contentStyle={{ borderRadius: 10, border: "1px solid #e5e9e5", boxShadow: "0 8px 24px #10241614" }} /><Area type="monotone" dataKey="users" name="Users" stroke="#15803d" strokeWidth={2.2} fill="url(#usersFill)" /></AreaChart></ResponsiveContainer></div> : <EmptyChart label="Registration totals will appear here." />}
        </article>

        <article className="card chart-card plan-card">
          <div className="card-heading"><div><h2>Plan mix</h2><p className="muted">Current subscriptions</p></div><button className="icon-button" aria-label="Refresh dashboard" onClick={() => void refresh()}><RefreshCw size={15} /></button></div>
          {planRows.length ? <div className="donut-wrap"><div className="donut-chart"><ResponsiveContainer width="100%" height="100%"><PieChart><Pie data={planRows} dataKey="value" nameKey="label" innerRadius="67%" outerRadius="94%" paddingAngle={3} stroke="none">{planRows.map((row, index) => <Cell key={row.key} fill={chartColors[index % chartColors.length]} />)}</Pie><Tooltip /></PieChart></ResponsiveContainer><div className="donut-center"><strong>{formatNumber(data.stats.totalUsers)}</strong><span>users</span></div></div><div className="plan-legend">{data.userBreakdown.byPlan.map((row, index) => <div className="plan-legend-row" key={row.key}><span><i style={{ background: chartColors[index % chartColors.length] }} />{row.label}</span><strong>{formatNumber(row.value)}</strong></div>)}</div></div> : <EmptyChart label="Subscription distribution will appear here." />}
          <div className="download-line"><span>App downloads</span><strong>{formatNumber(data.stats.downloadsTotal)}</strong><small>iOS {formatNumber(data.stats.downloadsIos)} · Android {formatNumber(data.stats.downloadsAndroid)}</small></div>
        </article>
      </section>

      <section className="overview-grid lower-grid">
        <article className="card table-card breakdown-card">
          <div className="card-heading"><div><h2>Registration source</h2><p className="muted">How users created their accounts</p></div></div>
          <div className="breakdown-list">{data.userBreakdown.byRegistrationType.map((row) => <div className="breakdown-row" key={row.key}><span>{row.label}</span><div className="breakdown-track"><i style={{ width: `${data.stats.totalUsers ? Math.max(2, row.value / data.stats.totalUsers * 100) : 0}%` }} /></div><strong>{formatNumber(row.value)}</strong></div>)}</div>
        </article>
        <article className="card table-card breakdown-card">
          <div className="card-heading"><div><h2>Device mix</h2><p className="muted">Registered account platforms</p></div></div>
          <div className="breakdown-list">{data.userBreakdown.byDeviceType.map((row) => <div className="breakdown-row" key={row.key}><span>{row.label}</span><div className="breakdown-track"><i style={{ width: `${data.stats.totalUsers ? Math.max(2, row.value / data.stats.totalUsers * 100) : 0}%` }} /></div><strong>{formatNumber(row.value)}</strong></div>)}</div>
        </article>
      </section>
    </div>
  );
}

function AppShell({ session, onLogout, onAuthExpired }: { session: AdminSession; onLogout: () => void; onAuthExpired: () => void }) {
  const [page, setPage] = useState<AdminPage>(() => {
    const requested = pageFromPath(window.location.pathname);
    return requested && canOpenPage(session.admin.role, requested) ? requested : defaultPage(session.admin.role);
  });

  useEffect(() => {
    function restoreRoute() {
      const requested = pageFromPath(window.location.pathname);
      const next = requested && canOpenPage(session.admin.role, requested)
        ? requested
        : defaultPage(session.admin.role);
      setPage(next);
      if (window.location.pathname !== routePaths[next]) {
        window.history.replaceState(null, "", routePaths[next]);
      }
    }

    window.addEventListener("popstate", restoreRoute);
    restoreRoute();
    return () => window.removeEventListener("popstate", restoreRoute);
  }, [session.admin.role]);

  const navigate = useCallback((next: AdminPage) => {
    if (!canOpenPage(session.admin.role, next)) return;
    window.history.pushState(null, "", routePaths[next]);
    setPage(next);
  }, [session.admin.role]);

  return (
    <AdminShell activePage={page} onNavigate={navigate} admin={session.admin} onLogout={onLogout}>
      {page === "overview" && session.admin.role === "owner" && <Overview token={session.token} onAuthExpired={onAuthExpired} />}
      {page === "users" && <UsersPage token={session.token} onAuthExpired={onAuthExpired} />}
      {page === "billing" && <BillingPage token={session.token} role={session.admin.role} onAuthExpired={onAuthExpired} />}
      {page === "llm" && <LLMPage token={session.token} role={session.admin.role} onAuthExpired={onAuthExpired} />}
      {page === "security" && <AdminSecurityPage token={session.token} onAuthExpired={onAuthExpired} />}
    </AdminShell>
  );
}

function App() {
  const [session, setSession] = useState<AdminSession | null>(readStoredSession);
  const [allowBootstrap, setAllowBootstrap] = useState(false);

  useEffect(() => {
    if (!isConfigured) return;
    let active = true;
    adminApi.bootstrapStatus()
      .then((status) => {
        if (active && typeof status.initialized === "boolean") {
          setAllowBootstrap(!status.initialized);
        }
      })
      .catch(() => {
        // Hide the setup action if the status endpoint cannot confirm it is safe.
        if (active) setAllowBootstrap(false);
      });
    return () => {
      active = false;
    };
  }, []);

  const clearSession = useCallback(() => {
    sessionStorage.removeItem(sessionStorageKey);
    setSession(null);
    window.history.replaceState(null, "", "/admin/login");
  }, []);

  useEffect(() => {
    const saved = readStoredSession();
    if (!saved || !isConfigured) {
      if (window.location.pathname.startsWith("/admin/") && window.location.pathname !== "/admin/login") {
        window.history.replaceState(null, "", "/admin/login");
      }
      return;
    }
    adminApi.session(saved.token).then(({ admin }) => setSession({ ...saved, admin })).catch(() => clearSession());
  }, [clearSession]);

  const acceptSession = useCallback((next: AdminSession) => {
    sessionStorage.setItem(sessionStorageKey, JSON.stringify(next));
    setSession(next);
    setAllowBootstrap(false);
    const requested = pageFromPath(window.location.pathname);
    const destination = requested && canOpenPage(next.admin.role, requested)
      ? requested
      : defaultPage(next.admin.role);
    window.history.replaceState(null, "", routePaths[destination]);
  }, []);

  const logout = useCallback(() => {
    if (session) void adminApi.logout(session.token).catch(() => undefined);
    clearSession();
  }, [clearSession, session]);

  if (!session) return <AdminLogin onLogin={acceptSession} allowBootstrap={allowBootstrap} />;
  if (session.admin.mustChangePassword) return <ChangePassword session={session} onUpdated={acceptSession} />;
  return <AppShell session={session} onLogout={logout} onAuthExpired={clearSession} />;
}

export default App;
