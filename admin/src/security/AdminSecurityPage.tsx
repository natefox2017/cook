// Developer: gengyun
// Purpose: Configure the signed-in administrator's TOTP and passkey factors.

import { useCallback, useEffect, useState, type FormEvent } from "react";
import { KeyRound, LoaderCircle, RefreshCw, ShieldCheck, Smartphone, Trash2 } from "lucide-react";
import { adminApi, handleExpiredSession } from "../api";
import type { AdminFactorState, AdminLoginEvent } from "../types";
import { createPasskey } from "./webauthn";
import "./AdminSecurityPage.css";

type AdminSecurityPageProps = { token: string; onAuthExpired: () => void };
type PendingTotp = { secret: string; otpauthUri: string };

export function AdminSecurityPage({ token, onAuthExpired }: AdminSecurityPageProps) {
  const [factors, setFactors] = useState<AdminFactorState | null>(null);
  const [events, setEvents] = useState<AdminLoginEvent[]>([]);
  const [pendingTotp, setPendingTotp] = useState<PendingTotp | null>(null);
  const [totpCode, setTotpCode] = useState("");
  const [currentPassword, setCurrentPassword] = useState("");
  const [passkeyName, setPasskeyName] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const load = useCallback(async () => {
    try {
      const [nextFactors, history] = await Promise.all([
        adminApi.securityFactors(token),
        adminApi.loginEvents(token),
      ]);
      setFactors(nextFactors);
      setEvents(history.data);
    } catch (cause) {
      handleExpiredSession(cause, onAuthExpired);
      setError(cause instanceof Error ? cause.message : "Unable to load security settings.");
    } finally {
      setLoading(false);
    }
  }, [token, onAuthExpired]);

  function refresh() {
    setLoading(true);
    setError("");
    void load();
  }

  useEffect(() => {
    let active = true;
    Promise.all([adminApi.securityFactors(token), adminApi.loginEvents(token)])
      .then(([value, history]) => {
        if (active) {
          setFactors(value);
          setEvents(history.data);
        }
      })
      .catch((cause: unknown) => {
        handleExpiredSession(cause, onAuthExpired);
        if (active) setError(cause instanceof Error ? cause.message : "Unable to load security settings.");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    const expire = () => onAuthExpired();
    window.addEventListener("admin-auth-expired", expire);
    return () => {
      active = false;
      window.removeEventListener("admin-auth-expired", expire);
    };
  }, [token, onAuthExpired]);

  async function run(action: string, operation: () => Promise<void>) {
    setBusy(action);
    setError("");
    setNotice("");
    try {
      await operation();
    } catch (cause) {
      handleExpiredSession(cause, onAuthExpired);
      setError(cause instanceof Error ? cause.message : "Security setting could not be updated.");
    } finally {
      setBusy("");
    }
  }

  async function beginTotp() {
    await run("totp-setup", async () => setPendingTotp(await adminApi.setupTotp(token, currentPassword)));
  }

  async function enableTotp(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await run("totp-verify", async () => {
      await adminApi.verifyTotp(token, totpCode.trim());
      setPendingTotp(null);
      setCurrentPassword("");
      setTotpCode("");
      setNotice("Authenticator app enabled.");
      await load();
    });
  }

  async function removeTotp(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await run("totp-remove", async () => {
      await adminApi.removeTotp(token, currentPassword, totpCode.trim());
      setCurrentPassword("");
      setTotpCode("");
      setNotice("Authenticator app removed.");
      await load();
    });
  }

  async function addPasskey() {
    await run("passkey-add", async () => {
      const { challengeId, options } = await adminApi.passkeyRegistrationOptions(token, currentPassword);
      const response = await createPasskey(options);
      await adminApi.verifyPasskeyRegistration(token, challengeId, response, passkeyName.trim() || "Passkey");
      setCurrentPassword("");
      setPasskeyName("");
      setNotice("Passkey added.");
      await load();
    });
  }

  async function removePasskey(credentialId: string) {
    if (!window.confirm("Remove this passkey from the administrator account?")) return;
    if (!currentPassword) {
      setError("Enter your current password before removing a passkey.");
      return;
    }
    await run(`passkey-remove-${credentialId}`, async () => {
      await adminApi.removePasskey(token, credentialId, currentPassword);
      setCurrentPassword("");
      setNotice("Passkey removed.");
      await load();
    });
  }

  return (
    <main className="security-page">
      <header className="security-heading page-heading-row">
        <div>
          <p className="eyebrow">ADMINISTRATION</p>
          <h1>Security</h1>
          <p className="muted">Add a second factor to protect this administrator account.</p>
        </div>
        <button type="button" className="button button-outline" onClick={refresh} disabled={loading}>
          <RefreshCw size={15} className={loading ? "spin" : ""} aria-hidden="true" /> Refresh
        </button>
      </header>

      {error && <div className="notice notice-warning" role="alert">{error}</div>}
      {notice && <div className="security-success" role="status"><ShieldCheck size={16} aria-hidden="true" />{notice}</div>}
      {loading && !factors ? (
        <div className="security-loading"><LoaderCircle size={17} className="spin" aria-hidden="true" /> Loading security settings…</div>
      ) : factors && (
        <>
          <section className="security-card card security-password-card" aria-labelledby="security-password-title">
            <div><h2 id="security-password-title">Confirm changes</h2><p>Enter your current password to add or remove an authentication factor.</p></div>
            <label htmlFor="factor-current-password">Current password</label>
            <input id="factor-current-password" type="password" autoComplete="current-password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} />
          </section>

          <section className="security-card card" aria-labelledby="security-totp-title">
            <div className="security-card-heading">
              <span className="security-icon"><Smartphone size={18} aria-hidden="true" /></span>
              <div><h2 id="security-totp-title">Authenticator app</h2><p>Use a time-based code from Google Authenticator or another compatible app.</p></div>
              <span className={`security-state ${factors.totp.enabled ? "enabled" : "disabled"}`}>{factors.totp.enabled ? "Enabled" : "Not set up"}</span>
            </div>
            {pendingTotp ? (
              <form className="security-form" onSubmit={enableTotp}>
                <p>Enter this key in your authenticator app, then verify a current six-digit code.</p>
                <label htmlFor="totp-secret">Setup key</label>
                <code id="totp-secret" className="security-secret">{pendingTotp.secret}</code>
                <label htmlFor="totp-setup-code">Verification code</label>
                <input id="totp-setup-code" autoComplete="one-time-code" inputMode="numeric" pattern="[0-9]{6}" maxLength={6} value={totpCode} onChange={(event) => setTotpCode(event.target.value)} required />
                <div className="security-actions">
                  <button className="button button-primary" disabled={busy !== ""}>{busy === "totp-verify" ? "Verifying…" : "Verify and enable"}</button>
                  <button className="button button-ghost" type="button" onClick={() => { setPendingTotp(null); setTotpCode(""); }}>Cancel</button>
                </div>
              </form>
            ) : factors.totp.enabled ? (
              <form className="security-form security-remove-form" onSubmit={removeTotp}>
                <p>Confirm your password and a current authenticator code to remove this factor.</p>
                <label htmlFor="totp-remove-code">Authenticator code</label>
                <input id="totp-remove-code" autoComplete="one-time-code" inputMode="numeric" pattern="[0-9]{6}" maxLength={6} value={totpCode} onChange={(event) => setTotpCode(event.target.value)} required />
                <button type="submit" className="button button-outline" disabled={busy !== ""}><Trash2 size={14} aria-hidden="true" /> Remove authenticator app</button>
              </form>
            ) : (
              <div className="security-card-footer">
                <p>Codes refresh every 30 seconds. Setup stays pending until the first code is verified.</p>
                <button type="button" className="button button-primary" onClick={() => void beginTotp()} disabled={busy !== "" || !currentPassword}>{busy === "totp-setup" ? "Preparing…" : "Set up authenticator app"}</button>
              </div>
            )}
          </section>

          <section className="security-card card" aria-labelledby="security-passkeys-title">
            <div className="security-card-heading">
              <span className="security-icon"><KeyRound size={18} aria-hidden="true" /></span>
              <div><h2 id="security-passkeys-title">Passkeys</h2><p>Sign in with biometrics, a device PIN, or a hardware security key.</p></div>
              <span className={`security-state ${factors.passkeys.length ? "enabled" : "disabled"}`}>{factors.passkeys.length} added</span>
            </div>
            {factors.passkeys.length > 0 && (
              <div className="security-passkey-list">
                {factors.passkeys.map((passkey) => (
                  <article className="security-passkey" key={passkey.credential_id}>
                    <div><strong>{passkey.name}</strong><span>Added {new Intl.DateTimeFormat("en", { dateStyle: "medium" }).format(new Date(passkey.created_at))}{passkey.last_used_at ? ` · Used ${new Intl.DateTimeFormat("en", { dateStyle: "medium" }).format(new Date(passkey.last_used_at))}` : ""}</span></div>
                    <button type="button" className="button button-ghost security-delete" disabled={busy !== ""} onClick={() => void removePasskey(passkey.credential_id)} aria-label={`Remove ${passkey.name}`}><Trash2 size={15} aria-hidden="true" /> Remove</button>
                  </article>
                ))}
              </div>
            )}
            <div className="security-card-footer security-passkey-footer">
              <label htmlFor="passkey-name">Passkey name</label>
              <input id="passkey-name" value={passkeyName} maxLength={80} placeholder="For example, MacBook Touch ID" onChange={(event) => setPasskeyName(event.target.value)} />
              <button type="button" className="button button-primary" disabled={busy !== "" || !currentPassword} onClick={() => void addPasskey()}>{busy === "passkey-add" ? "Waiting for device…" : "Add passkey"}</button>
            </div>
          </section>

          <section className="security-card card" aria-labelledby="security-login-history-title">
            <div className="security-card-heading">
              <span className="security-icon"><ShieldCheck size={18} aria-hidden="true" /></span>
              <div><h2 id="security-login-history-title">Login history</h2><p>Recent successful and failed administrator authentication attempts.</p></div>
            </div>
            {events.length ? (
              <div className="security-event-list">
                {events.map((event) => (
                  <article className="security-event" key={event.id}>
                    <div className="security-event-main">
                      <strong>{event.method.toUpperCase()} · {event.success ? "Successful" : "Failed"}</strong>
                      <span>{new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(event.createdAt))}{event.failureReason ? ` · ${event.failureReason.replaceAll("_", " ")}` : ""}</span>
                    </div>
                    <div className="security-event-meta"><span>{event.ipAddress || "IP unavailable"}</span><span title={event.userAgent ?? undefined}>{event.userAgent || "Device details unavailable"}</span></div>
                  </article>
                ))}
              </div>
            ) : <p className="security-empty-events">No login events recorded yet.</p>}
          </section>

        </>
      )}
    </main>
  );
}
