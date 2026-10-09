import { useState, type ReactNode } from "react";
import {
  Activity,
  BookOpen,
  ChevronDown,
  CircleDollarSign,
  LayoutDashboard,
  LogOut,
  Menu,
  ShieldCheck,
  Users,
  X,
} from "lucide-react";
import type { AdminAccount } from "../types";
import "./AdminShell.css";

export type AdminPage = "overview" | "users" | "billing" | "llm" | "security";

type AdminShellProps = {
  activePage: AdminPage;
  onNavigate: (page: AdminPage) => void;
  admin: AdminAccount;
  onLogout: () => void;
  children: ReactNode;
};

const pageLabels: Record<AdminPage, string> = {
  overview: "Overview",
  users: "Users",
  billing: "Subscriptions",
  llm: "AI Models",
  security: "Security",
};

function roleLabel(role: AdminAccount["role"]) {
  return role === "owner" ? "Owner" : role === "admin" ? "Admin" : role === "operator" ? "Operator" : "Read only";
}

export default function AdminShell({ activePage, onNavigate, admin, onLogout, children }: AdminShellProps) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [accountMenuOpen, setAccountMenuOpen] = useState(false);
  const navItems = [
    ...(admin.role === "owner" ? [{ id: "overview" as const, label: pageLabels.overview, icon: LayoutDashboard }] : []),
    ...(["owner", "admin"].includes(admin.role) ? [{ id: "users" as const, label: pageLabels.users, icon: Users }] : []),
    { id: "billing" as const, label: pageLabels.billing, icon: CircleDollarSign },
    ...(["owner", "admin"].includes(admin.role) ? [{ id: "llm" as const, label: pageLabels.llm, icon: Activity }] : []),
    { id: "security" as const, label: pageLabels.security, icon: ShieldCheck },
  ];

  function navigate(page: AdminPage) {
    onNavigate(page);
    setMenuOpen(false);
  }

  return (
    <div className="admin-shell">
      <aside className={`admin-sidebar${menuOpen ? " admin-sidebar-open" : ""}`}>
        <div className="admin-sidebar-brand">
          <div className="admin-brand">
            <span className="admin-brand-mark"><BookOpen size={17} strokeWidth={2.2} /></span>
            <span>Recipe Pals</span>
          </div>
          <button className="admin-icon-button admin-mobile-close" type="button" aria-label="Close navigation" onClick={() => setMenuOpen(false)}>
            <X size={17} />
          </button>
        </div>

        <div className="admin-workspace-label">WORKSPACE</div>
        <nav aria-label="Main navigation" className="admin-side-nav">
          {navItems.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              type="button"
              className={`admin-nav-item${activePage === id ? " admin-nav-item-active" : ""}`}
              aria-current={activePage === id ? "page" : undefined}
              onClick={() => navigate(id)}
            >
              <Icon size={17} />
              <span>{label}</span>
              {id === "overview" && <span className="admin-nav-dot" aria-hidden="true" />}
            </button>
          ))}
        </nav>

        <div className="admin-sidebar-bottom">
          <div className="admin-sidebar-help">
            <span className="admin-help-icon"><ShieldCheck size={16} /></span>
            <div><strong>Secure workspace</strong><small>Access is role controlled</small></div>
          </div>
          <div className="admin-sidebar-version"><span>Recipe Pals Admin</span><span>v1</span></div>
        </div>
      </aside>

      {menuOpen && <button className="admin-sidebar-scrim" type="button" aria-label="Close navigation" onClick={() => setMenuOpen(false)} />}

      <div className="admin-main-column">
        <header className="admin-topbar">
          <div className="admin-topbar-left">
            <button className="admin-icon-button admin-mobile-menu" type="button" aria-label="Open navigation" onClick={() => setMenuOpen(true)}>
              <Menu size={18} />
            </button>
            <nav className="admin-breadcrumb" aria-label="Breadcrumb">
              <span className="admin-breadcrumb-muted">Workspace</span>
              <span className="admin-crumb-divider" aria-hidden="true">/</span>
              <strong aria-current="page">{pageLabels[activePage]}</strong>
            </nav>
          </div>

          <div className="admin-topbar-right">
            <span className="admin-status-pill"><i aria-hidden="true" /> Connected</span>
            <details
              className="admin-account-menu"
              open={accountMenuOpen}
              onToggle={(event) => setAccountMenuOpen(event.currentTarget.open)}
            >
              <summary className="admin-account-trigger" aria-label={`Account: ${admin.username} (${roleLabel(admin.role)})`}>
                <span className="admin-avatar" aria-hidden="true">{admin.username.slice(0, 1).toUpperCase()}</span>
                <span className="admin-account-copy"><strong>{admin.username}</strong><small>{roleLabel(admin.role)}</small></span>
                <ChevronDown size={14} className="admin-account-chevron" aria-hidden="true" />
              </summary>
              <div className="admin-account-panel">
                <div className="admin-account-identity">
                  <span className="admin-avatar" aria-hidden="true">{admin.username.slice(0, 1).toUpperCase()}</span>
                  <span><strong>{admin.username}</strong><small>{roleLabel(admin.role)} account</small></span>
                </div>
                <div className="admin-account-divider" />
                <button className="admin-account-logout" type="button" onClick={onLogout}>
                  <LogOut size={16} aria-hidden="true" />
                  <span>Sign out</span>
                </button>
              </div>
            </details>
          </div>
        </header>

        <main className="admin-main-content">{children}</main>
      </div>
    </div>
  );
}
