import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import {
  Activity,
  ArrowUpRight,
  BookOpen,
  ChevronDown,
  CircleDollarSign,
  LayoutDashboard,
  LogOut,
  Menu,
  RefreshCw,
  ShieldCheck,
  Users,
  X,
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
import type { AdminRole, AdminSession, DashboardData } from "./types";
import UsersPage from "./pages/UsersPage";
import BillingPage from "./pages/BillingPage";
import { LLMPage } from "./pages/LLMPage";
import "./App.css";

type Page = "overview" | "users" | "billing" | "llm";

const sessionStorageKey = "recipe.admin.session";
const chartColors = ["#16a34a", "#86efac", "#d1d5db"];

function roleLabel(role: AdminRole) {
  return role === "owner" ? "Owner" : role === "admin" ? "Admin" : role === "operator" ? "Operator" : "Read only";
}

function formatNumber(value: number) {
  return new Intl.NumberFormat("en-US", { notation: value > 9999 ? "compact" : "standard" }).format(value);
}

function formatMoney(value: number) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 }).format(value);
}

function Login({ onLogin }: { onLogin: (session: AdminSession) => void }) {
  const [mode, setMode] = useState<"login" | "bootstrap">("login");
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("");
  const [currentPassword, setCurrentPassword] = useState("");
  const [bootstrapToken, setBootstrapToken] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    if (mode === "bootstrap" && password !== confirmation) {
      setError("The new passwords do not match.");
      return;
    }
    if (mode === "bootstrap") {
      if (password.length < 12) {
        setError("The new password must be at least 12 characters.");
        return;
      }
      if (!/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) {
        setError("Include at least one uppercase letter, one lowercase letter, and one number.");
        return;
      }
      if (["admin", "password", "password123", "cookappadmin", "adminadmin"].includes(password.toLowerCase())) {
        setError("Choose a less common password.");
        return;
      }
    }
    setLoading(true);
    try {
      const session = mode === "bootstrap"
        ? await adminApi.bootstrap(username.trim(), password, bootstrapToken, currentPassword)
        : await adminApi.login(username.trim(), password);
      setPassword("");
      setCurrentPassword("");
      setBootstrapToken("");
      setConfirmation("");
      onLogin(session);
    } catch (cause) {
      setPassword("");
      setCurrentPassword("");
      setBootstrapToken("");
      setConfirmation("");
      setError(cause instanceof Error ? cause.message : "Sign in failed. Try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="login-shell">
      <div className="login-card card">
        <div className="brand brand-login">
          <span className="brand-mark"><BookOpen size={18} strokeWidth={2.2} /></span>
          <span>RecipePouch</span>
        </div>
        <p className="eyebrow">ADMINISTRATION</p>
        <h1>Welcome back</h1>
        <p className="muted login-copy">{mode === "login" ? "Sign in with your RecipePouch admin account." : "Initialize the owner account for this Supabase project."}</p>
        {!isConfigured && <div className="notice notice-warning">Set <code>VITE_ADMIN_FUNCTIONS_URL</code> and <code>VITE_SUPABASE_PUBLISHABLE_KEY</code> in <code>admin/.env.local</code> to connect Supabase.</div>}
        {mode === "bootstrap" && <div className="notice notice-warning">Requires the bootstrap token configured in Supabase Edge Function secrets. The new password must be at least 12 characters and include uppercase, lowercase, and a number.</div>}
        <form onSubmit={submit} className="login-form">
          <label htmlFor="username">Username</label>
          <input id="username" autoComplete="username" value={username} onChange={(event) => setUsername(event.target.value)} required />
          <label htmlFor="password">{mode === "login" ? "Password" : "New owner password"}</label>
          <input id="password" type="password" autoComplete={mode === "login" ? "current-password" : "new-password"} minLength={mode === "bootstrap" ? 12 : undefined} value={password} onChange={(event) => setPassword(event.target.value)} required />
          {mode === "bootstrap" && <>
            <label htmlFor="confirm-owner-password">Confirm new password</label>
            <input id="confirm-owner-password" type="password" autoComplete="new-password" minLength={12} value={confirmation} onChange={(event) => setConfirmation(event.target.value)} required />
            <label htmlFor="bootstrap-token">Supabase bootstrap token</label>
            <input id="bootstrap-token" type="password" autoComplete="off" value={bootstrapToken} onChange={(event) => setBootstrapToken(event.target.value)} required />
            <label htmlFor="current-seed-password">Current seed password <span className="muted">(only if converting the default seed)</span></label>
            <input id="current-seed-password" type="password" autoComplete="current-password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} />
          </>}
          {error && <p className="form-error" role="alert">{error}</p>}
          <button className="button button-primary login-submit" disabled={loading || !isConfigured}>
            {loading ? <><span className="spinner" /> {mode === "login" ? "Signing in" : "Initializing"}</> : mode === "login" ? "Sign in" : "Initialize owner account"}
          </button>
        </form>
        {isConfigured && <button className="button button-ghost login-mode-toggle" type="button" onClick={() => { setMode(mode === "login" ? "bootstrap" : "login"); setError(""); setPassword(""); setCurrentPassword(""); setBootstrapToken(""); setConfirmation(""); }}>
          {mode === "login" ? "First time here? Initialize admin" : "Back to sign in"}
        </button>}
        <div className="login-security"><ShieldCheck size={15} /> Admin session protected by the RecipePouch backend</div>
      </div>
      <footer className="login-footer">RecipePouch · Internal admin</footer>
    </main>
  );
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
        <MetricCard label="Registrations this month" value={formatNumber(data.stats.newUsersThisMonth)} note="New admin accounts" icon={ArrowUpRight} tone="blue" />
        <MetricCard label="Active paid" value={formatNumber(data.stats.activePaidUsers)} note={`${formatNumber(data.stats.suspendedUsers)} suspended accounts`} icon={ArrowUpRight} tone="amber" />
        <MetricCard label="Revenue tracked" value={formatMoney(data.stats.revenueTotal)} note={`${formatMoney(data.stats.revenueMrr)} estimated MRR`} icon={CircleDollarSign} tone="violet" />
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
  const [page, setPage] = useState<Page>(session.admin.role === "owner" ? "overview" : session.admin.role === "admin" ? "users" : "billing");
  const [menuOpen, setMenuOpen] = useState(false);
  const navItems = useMemo(() => [
    ...(session.admin.role === "owner" ? [{ id: "overview" as const, label: "Overview", icon: LayoutDashboard }] : []),
    ...(["owner", "admin"].includes(session.admin.role) ? [{ id: "users" as const, label: "Users", icon: Users }] : []),
    { id: "billing" as const, label: "Subscriptions", icon: CircleDollarSign },
    ...(["owner", "admin"].includes(session.admin.role) ? [{ id: "llm" as const, label: "AI Models", icon: Activity }] : []),
  ], [session.admin.role]);

  const pageTitle = page === "overview" ? "Overview" : page === "users" ? "Users" : page === "billing" ? "Subscriptions" : "AI Models";

  return (
    <div className="app-shell">
      <aside className={`sidebar ${menuOpen ? "sidebar-open" : ""}`}>
        <div className="sidebar-brand"><div className="brand"><span className="brand-mark"><BookOpen size={17} strokeWidth={2.2} /></span><span>RecipePouch</span></div><button className="icon-button mobile-close" aria-label="Close navigation" onClick={() => setMenuOpen(false)}><X size={17} /></button></div>
        <div className="workspace-label">WORKSPACE</div>
        <nav aria-label="Main navigation" className="side-nav">{navItems.map((item) => { const Icon = item.icon; return <button key={item.id} className={`nav-item ${page === item.id ? "nav-item-active" : ""}`} onClick={() => { setPage(item.id); setMenuOpen(false); }}><Icon size={17} /><span>{item.label}</span>{item.id === "overview" && <span className="nav-dot" />}</button>; })}</nav>
        <div className="sidebar-bottom"><div className="sidebar-help"><span className="help-icon"><ShieldCheck size={16} /></span><div><strong>Secure workspace</strong><small>Access is role controlled</small></div></div><div className="sidebar-version">RecipePouch Admin <span>v1</span></div></div>
      </aside>
      {menuOpen && <button className="sidebar-scrim" aria-label="Close navigation" onClick={() => setMenuOpen(false)} />}
      <div className="main-column">
        <header className="topbar"><div className="topbar-left"><button className="icon-button mobile-menu" aria-label="Open navigation" onClick={() => setMenuOpen(true)}><Menu size={18} /></button><span className="breadcrumb-muted">Workspace</span><span className="crumb-divider">/</span><strong>{pageTitle}</strong></div><div className="topbar-right"><span className="status-pill"><i /> Connected</span><div className="account-menu"><span className="avatar">{session.admin.username.slice(0, 1).toUpperCase()}</span><span className="account-copy"><strong>{session.admin.username}</strong><small>{roleLabel(session.admin.role)}</small></span><button className="icon-button" aria-label="Sign out" title="Sign out" onClick={onLogout}><LogOut size={16} /></button><ChevronDown size={13} className="account-chevron" /></div></div></header>
        <main className="main-content">
          {page === "overview" && session.admin.role === "owner" && <Overview token={session.token} onAuthExpired={onAuthExpired} />}
          {page === "users" && <UsersPage token={session.token} onAuthExpired={onAuthExpired} />}
          {page === "billing" && <BillingPage token={session.token} role={session.admin.role} onAuthExpired={onAuthExpired} />}
          {page === "llm" && <LLMPage token={session.token} role={session.admin.role} onAuthExpired={onAuthExpired} />}
        </main>
      </div>
    </div>
  );
}

function App() {
  const [session, setSession] = useState<AdminSession | null>(null);
  const [restoring, setRestoring] = useState(true);

  const clearSession = useCallback(() => {
    sessionStorage.removeItem(sessionStorageKey);
    setSession(null);
  }, []);

  useEffect(() => {
    const raw = sessionStorage.getItem(sessionStorageKey);
    if (!raw || !isConfigured) {
      setRestoring(false);
      return;
    }
    let saved: AdminSession;
    try {
      saved = JSON.parse(raw) as AdminSession;
    } catch {
      sessionStorage.removeItem(sessionStorageKey);
      setRestoring(false);
      return;
    }
    if (Date.parse(saved.expiresAt) <= Date.now()) {
      sessionStorage.removeItem(sessionStorageKey);
      setRestoring(false);
      return;
    }
    adminApi.session(saved.token).then(({ admin }) => setSession({ ...saved, admin })).catch(() => clearSession()).finally(() => setRestoring(false));
  }, [clearSession]);

  const acceptSession = useCallback((next: AdminSession) => {
    sessionStorage.setItem(sessionStorageKey, JSON.stringify(next));
    setSession(next);
  }, []);

  const logout = useCallback(() => {
    if (session) void adminApi.logout(session.token).catch(() => undefined);
    clearSession();
  }, [clearSession, session]);

  if (restoring) return <div className="boot-screen"><span className="spinner" /> Checking admin session…</div>;
  if (!session) return <Login onLogin={acceptSession} />;
  if (session.admin.mustChangePassword) return <ChangePassword session={session} onUpdated={acceptSession} />;
  return <AppShell session={session} onLogout={logout} onAuthExpired={clearSession} />;
}

export default App;
