// Developer: gengyun
// Purpose: Manage read-only user browsing and account detail inspection.

import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { Search, X } from "lucide-react";
import { adminApi, handleExpiredSession } from "../api";
import type { AdminUser, AdminUserDetail, AdminUserPage } from "../types";
import "./UsersPage.css";

export type UsersPageProps = {
  token: string;
  onAuthExpired: () => void;
};

type UserStatus = "all" | AdminUser["status"];
type Subscription = "all" | AdminUser["subscription"];
type Provider = "all" | AdminUser["registrationProvider"];
type Device = "all" | AdminUser["deviceType"];

const pageSize = 20;

function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.valueOf())
    ? "—"
    : new Intl.DateTimeFormat("en", { dateStyle: "medium" }).format(date);
}

function titleCase(value: string): string {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function initials(user: AdminUser): string {
  const name = user.displayName.trim();
  return name && name !== "Unknown"
    ? name.split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase()
    : (user.email[0] ?? "U").toUpperCase();
}

export default function UsersPage({ token, onAuthExpired }: UsersPageProps) {
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<UserStatus>("all");
  const [subscription, setSubscription] = useState<Subscription>("all");
  const [provider, setProvider] = useState<Provider>("all");
  const [device, setDevice] = useState<Device>("all");
  const [page, setPage] = useState(1);
  const [users, setUsers] = useState<AdminUserPage | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedUser, setSelectedUser] = useState<AdminUser | AdminUserDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);
  const dialogRef = useRef<HTMLDialogElement>(null);
  const requestId = useRef(0);

  useEffect(() => {
    const timer = window.setTimeout(() => setQuery(search.trim()), 250);
    return () => window.clearTimeout(timer);
  }, [search]);

  useEffect(() => {
    setPage(1);
  }, [query, status, subscription, provider, device]);

  useEffect(() => {
    let current = true;
    const params = new URLSearchParams({ page: String(page), pageSize: String(pageSize) });
    if (query) params.set("q", query);
    if (status !== "all") params.set("status", status);
    if (subscription !== "all") params.set("subscription", subscription);
    if (provider !== "all") params.set("registrationProvider", provider);
    if (device !== "all") params.set("deviceType", device);

    setLoading(true);
    setError(null);
    const thisRequest = ++requestId.current;
    void adminApi.users(token, params)
      .then((result) => {
        if (current && requestId.current === thisRequest) setUsers(result);
      })
      .catch((reason: unknown) => {
        if (!current || requestId.current !== thisRequest) return;
        handleExpiredSession(reason, onAuthExpired);
        setError(reason instanceof Error ? reason.message : "Could not load users.");
      })
      .finally(() => {
        if (current && requestId.current === thisRequest) setLoading(false);
      });
    return () => { current = false; };
  }, [token, onAuthExpired, query, status, subscription, provider, device, page]);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (selectedUser && !dialog.open) dialog.showModal();
    if (!selectedUser && dialog.open) dialog.close();
  }, [selectedUser]);

  async function openUser(user: AdminUser) {
    setSelectedUser(user);
    setDetailLoading(true);
    setDetailError(null);
    try {
      setSelectedUser(await adminApi.user(token, user.id));
    } catch (reason) {
      handleExpiredSession(reason, onAuthExpired);
      setDetailError(reason instanceof Error ? reason.message : "Could not load user details.");
    } finally {
      setDetailLoading(false);
    }
  }

  const totalPages = Math.max(1, Math.ceil((users?.total ?? 0) / pageSize));
  const rangeStart = users?.total ? (page - 1) * pageSize + 1 : 0;
  const rangeEnd = Math.min(page * pageSize, users?.total ?? 0);

  return (
    <main className="users-page">
      <header className="users-heading">
        <div>
          <p className="users-eyebrow">Administration</p>
          <h1>Users</h1>
          <p className="users-subtitle">Review accounts, registration sources, and subscription details.</p>
        </div>
        <div className="users-total-badge" aria-label={`${users?.total ?? 0} users in current results`}>
          <span className="users-total-dot" />
          {new Intl.NumberFormat("en").format(users?.total ?? 0)} users
        </div>
      </header>

      <section className="users-panel" aria-labelledby="users-list-title">
        <div className="users-panel-header">
          <div>
            <h2 id="users-list-title">All users</h2>
            <p>Search and filter account records.</p>
          </div>
          <label className="users-search">
            <Search size={17} aria-hidden="true" />
            <span className="sr-only">Search users</span>
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search name or email" />
          </label>
        </div>

        <div className="users-filters" aria-label="User filters">
          <Filter label="Status" value={status} onChange={(value) => setStatus(value as UserStatus)} options={[
            ["all", "All statuses"], ["active", "Active"], ["suspended", "Suspended"], ["deleted", "Deleted"],
          ]} />
          <Filter label="Plan" value={subscription} onChange={(value) => setSubscription(value as Subscription)} options={[
            ["all", "All plans"], ["free", "Free"], ["pro", "Pro"], ["lifetime", "Lifetime"],
          ]} />
          <Filter label="Provider" value={provider} onChange={(value) => setProvider(value as Provider)} options={[
            ["all", "All providers"], ["apple", "Apple"], ["google", "Google"], ["email", "Email"], ["unknown", "Unknown"],
          ]} />
          <Filter label="Device" value={device} onChange={(value) => setDevice(value as Device)} options={[
            ["all", "All devices"], ["ios", "iOS"], ["android", "Android"], ["web", "Web"], ["unknown", "Unknown"],
          ]} />
          {(status !== "all" || subscription !== "all" || provider !== "all" || device !== "all" || search) && (
            <button className="users-reset" type="button" onClick={() => {
              setSearch(""); setStatus("all"); setSubscription("all"); setProvider("all"); setDevice("all");
            }}>Reset filters</button>
          )}
        </div>

        {error && <div className="users-alert" role="alert">{error}</div>}
        <div className="users-table-wrap">
          <table className="users-table">
            <thead>
              <tr><th scope="col">User</th><th scope="col">Plan</th><th scope="col">Status</th><th scope="col">Provider</th><th scope="col">Device</th><th scope="col">Joined</th><th scope="col"><span className="sr-only">Actions</span></th></tr>
            </thead>
            <tbody>
              {loading && <tr><td className="users-empty" colSpan={7}>Loading users…</td></tr>}
              {!loading && users?.data.map((user) => (
                <tr key={user.id}>
                  <td>
                    <button className="users-identity" type="button" onClick={() => void openUser(user)} aria-label={`View ${user.displayName}, ${user.email}`}>
                      {user.avatarUrl ? <img className="users-avatar" src={user.avatarUrl} alt="" /> : <span className="users-avatar users-avatar-fallback">{initials(user)}</span>}
                      <span className="users-identity-copy"><strong>{user.displayName}</strong><span>{user.email || "No email"}</span></span>
                    </button>
                  </td>
                  <td><span className={`users-plan users-plan-${user.subscription}`}>{titleCase(user.subscription)}</span></td>
                  <td><span className={`users-status users-status-${user.status}`}><i />{titleCase(user.status)}</span></td>
                  <td>{titleCase(user.registrationProvider)}</td>
                  <td>{user.deviceType === "ios" ? "iOS" : titleCase(user.deviceType)}</td>
                  <td>{formatDate(user.createdAt)}</td>
                  <td><button className="users-open" type="button" onClick={() => void openUser(user)}>View</button></td>
                </tr>
              ))}
              {!loading && !error && !users?.data.length && <tr><td className="users-empty" colSpan={7}>No users match these filters.</td></tr>}
            </tbody>
          </table>
        </div>

        <footer className="users-pagination">
          <span>Showing {rangeStart}–{rangeEnd} of {users?.total ?? 0} users</span>
          <div className="users-page-controls">
            <button type="button" onClick={() => setPage((value) => Math.max(1, value - 1))} disabled={page <= 1 || loading}>Previous</button>
            <span>Page {page} of {totalPages}</span>
            <button type="button" onClick={() => setPage((value) => Math.min(totalPages, value + 1))} disabled={page >= totalPages || loading}>Next</button>
          </div>
        </footer>
      </section>

      <dialog className="users-drawer" ref={dialogRef} onClose={() => setSelectedUser(null)} aria-labelledby="user-detail-title">
        <div className="users-drawer-header">
          <div><p className="users-eyebrow">Account details</p><h2 id="user-detail-title">User profile</h2></div>
          <button className="users-icon-button" type="button" onClick={() => setSelectedUser(null)} aria-label="Close user details"><X size={19} /></button>
        </div>
        {detailLoading && <p className="users-detail-state">Loading account details…</p>}
        {detailError && <div className="users-alert" role="alert">{detailError}</div>}
        {selectedUser && <UserDetails user={selectedUser} />}
      </dialog>
    </main>
  );
}

function Filter({ label, value, onChange, options }: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: Array<[string, string]>;
}) {
  return <label className="users-filter"><span className="sr-only">{label}</span><select aria-label={label} value={value} onChange={(event) => onChange(event.target.value)}>
    {options.map(([option, text]) => <option key={option} value={option}>{text}</option>)}
  </select></label>;
}

function UserDetails({ user }: { user: AdminUser | AdminUserDetail }) {
  return <>
    <div className="users-detail-person">
      {user.avatarUrl ? <img className="users-avatar users-avatar-large" src={user.avatarUrl} alt="" /> : <span className="users-avatar users-avatar-large users-avatar-fallback">{initials(user)}</span>}
      <div><strong>{user.displayName}</strong><span>{user.email || "No email"}</span></div>
    </div>
    <section className="users-detail-section"><h3>Account</h3><dl className="users-detail-grid">
      <Detail label="Status">{titleCase(user.status)}</Detail>
      <Detail label="Subscription">{titleCase(user.subscription)}</Detail>
      <Detail label="Joined">{formatDate(user.createdAt)}</Detail>
      <Detail label="Last login">{"lastLoginAt" in user ? formatDate(user.lastLoginAt) : "—"}</Detail>
      <Detail label="Provider">{titleCase(user.registrationProvider)}</Detail>
      <Detail label="Device">{user.deviceType === "ios" ? "iOS" : titleCase(user.deviceType)}</Detail>
      <Detail label="Country">{user.registrationCountryCode || "Unavailable"}</Detail>
    </dl></section>
    <section className="users-detail-section"><h3>Payment history</h3>
      {"payments" in user && user.payments.length ? <ul className="users-payment-list">{user.payments.map((payment) => <li key={payment.id}>
        <div><strong>{payment.productId || payment.eventType || "Payment"}</strong><span>{payment.store ? titleCase(payment.store.replace("_", " ")) : "Store unavailable"} · {formatDate(payment.purchasedAt)}</span></div>
        <span>{payment.amount === null ? "—" : `${payment.currency ?? ""} ${payment.amount}`.trim()}</span>
      </li>)}</ul> : <p className="users-detail-state">{"payments" in user ? "No payment records." : "Payment history unavailable."}</p>}
    </section>
  </>;
}

function Detail({ label, children }: { label: string; children: ReactNode }) {
  return <div><dt>{label}</dt><dd>{children}</dd></div>;
}
