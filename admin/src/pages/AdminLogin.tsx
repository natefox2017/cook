import { useState, type FormEvent } from "react";
import { ShieldCheck } from "lucide-react";
import appIconUrl from "../assets/recipepouch-app-icon.png";
import { adminApi, isConfigured } from "../api";
import type { AdminSession } from "../types";
import { getPasskeyCredential } from "../security/webauthn";
import "./AdminLogin.css";

type AdminLoginProps = {
  onLogin: (session: AdminSession) => void;
  allowBootstrap: boolean;
};

export function AdminLogin({ onLogin, allowBootstrap }: AdminLoginProps) {
  const [mode, setMode] = useState<"login" | "bootstrap">("login");
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("");
  const [currentPassword, setCurrentPassword] = useState("");
  const [bootstrapToken, setBootstrapToken] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [factorChallenge, setFactorChallenge] = useState<{ challengeToken: string; methods: Array<"totp" | "passkey"> } | null>(null);
  const [factorCode, setFactorCode] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    if (!factorChallenge && mode === "bootstrap" && password !== confirmation) {
      setError("The new passwords do not match.");
      return;
    }
    if (!factorChallenge && mode === "bootstrap") {
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
      if (factorChallenge) {
        const session = await adminApi.loginTotp(factorChallenge.challengeToken, factorCode.trim());
        setFactorChallenge(null);
        setFactorCode("");
        onLogin(session);
        return;
      }
      const session = mode === "bootstrap"
        ? await adminApi.bootstrap(username.trim(), password, bootstrapToken, currentPassword)
        : await adminApi.login(username.trim(), password);
      if ("factorRequired" in session) {
        setFactorChallenge({ challengeToken: session.challengeToken, methods: session.methods });
        setPassword("");
        setCurrentPassword("");
        setBootstrapToken("");
        setConfirmation("");
        return;
      }
      setPassword("");
      setCurrentPassword("");
      setBootstrapToken("");
      setConfirmation("");
      setFactorCode("");
      setFactorChallenge(null);
      onLogin(session);
    } catch (cause) {
      if (!factorChallenge) {
        setPassword("");
        setCurrentPassword("");
        setBootstrapToken("");
        setConfirmation("");
      }
      setFactorCode("");
      setError(cause instanceof Error ? cause.message : "Sign in failed. Try again.");
    } finally {
      setLoading(false);
    }
  }

  function toggleMode() {
    setFactorChallenge(null);
    setFactorCode("");
    setMode(mode === "login" ? "bootstrap" : "login");
    setError("");
    setPassword("");
    setCurrentPassword("");
    setBootstrapToken("");
    setConfirmation("");
  }

  async function signInWithPasskey() {
    setError("");
    setLoading(true);
    try {
      const { challengeId, options } = await adminApi.loginPasskeyOptions(
        username.trim(),
        factorChallenge?.challengeToken,
      );
      const response = await getPasskeyCredential(options);
      const session = await adminApi.loginPasskeyVerify(challengeId, response);
      setFactorChallenge(null);
      onLogin(session);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Passkey sign in failed.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="admin-login-shell">
      <section className="admin-login-card" aria-labelledby="admin-login-title">
        <a className="admin-login-brand" href="/" aria-label="Recipe Pals admin home">
          <span className="brand-mark" aria-hidden="true">
            <img src={appIconUrl} alt="" />
          </span>
          <span>Recipe Pals</span>
        </a>
        <h1 id="admin-login-title">{factorChallenge ? "Two-step verification" : mode === "login" ? "Sign in" : "Set up your owner account"}</h1>

        {!isConfigured && (
          <div className="admin-login-notice" role="status">
            Set <code>VITE_ADMIN_FUNCTIONS_URL</code> and <code>VITE_SUPABASE_PUBLISHABLE_KEY</code> in <code>admin/.env.local</code> to connect Supabase.
          </div>
        )}
        {!factorChallenge && mode === "bootstrap" && (
          <div className="admin-login-notice" id="owner-password-guidance">
          Bootstrap token required. Password: 12+ characters with uppercase, lowercase, and a number.
          </div>
        )}

        <form className="admin-login-form" onSubmit={submit} aria-busy={loading}>
          {!factorChallenge && <>
          <label htmlFor="admin-login-username">Username</label>
          <input
            id="admin-login-username"
            name="username"
            autoComplete="username"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
            required
          />

          <label htmlFor="admin-login-password">
            {mode === "login" ? "Password" : "New owner password"}
          </label>
          <input
            id="admin-login-password"
            name="password"
            type="password"
            autoComplete={mode === "login" ? "current-password" : "new-password"}
            minLength={mode === "bootstrap" ? 12 : undefined}
            aria-describedby={mode === "bootstrap" ? "owner-password-guidance" : undefined}
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
          </>}

          {factorChallenge && factorChallenge.methods.includes("totp") && (
            <>
              <label htmlFor="admin-login-factor-code">Authenticator code</label>
              <input
                id="admin-login-factor-code"
                name="factor-code"
                autoComplete="one-time-code"
                inputMode="numeric"
                pattern="[0-9]{6}"
                maxLength={6}
                value={factorCode}
                onChange={(event) => setFactorCode(event.target.value)}
                required
              />
            </>
          )}

          {!factorChallenge && mode === "bootstrap" && (
            <>
              <label htmlFor="admin-login-confirm-password">Confirm new password</label>
              <input
                id="admin-login-confirm-password"
                name="confirm-password"
                type="password"
                autoComplete="new-password"
                minLength={12}
                value={confirmation}
                onChange={(event) => setConfirmation(event.target.value)}
                required
              />

              <label htmlFor="admin-login-bootstrap-token">Supabase bootstrap token</label>
              <input
                id="admin-login-bootstrap-token"
                name="bootstrap-token"
                type="password"
                autoComplete="off"
                value={bootstrapToken}
                onChange={(event) => setBootstrapToken(event.target.value)}
                required
              />

              <label htmlFor="admin-login-current-password">
                Current seed password <span>(only if converting the default seed)</span>
              </label>
              <input
                id="admin-login-current-password"
                name="current-seed-password"
                type="password"
                autoComplete="current-password"
                value={currentPassword}
                onChange={(event) => setCurrentPassword(event.target.value)}
              />
            </>
          )}

          {error && <p className="admin-login-error" role="alert">{error}</p>}
          {(!factorChallenge || factorChallenge.methods.includes("totp")) && <button className="button button-primary admin-login-submit" disabled={loading || !isConfigured}>
            {loading ? (
              <>
                <span className="spinner" aria-hidden="true" />
                <span role="status">{factorChallenge ? "Verifying" : mode === "login" ? "Signing in" : "Initializing"}</span>
              </>
            ) : factorChallenge ? "Verify code" : mode === "login" ? "Sign in" : "Initialize owner account"}
          </button>}
        </form>

        {(factorChallenge?.methods.includes("passkey") || (!factorChallenge && mode === "login")) && (
          <button className="button button-outline admin-login-submit" type="button" onClick={() => void signInWithPasskey()} disabled={loading || !isConfigured || !username.trim()}>
            {loading ? "Waiting for passkey…" : "Sign in with passkey"}
          </button>
        )}

        {isConfigured && allowBootstrap && (
          <button className="button button-ghost admin-login-mode-toggle" type="button" onClick={toggleMode}>
            {factorChallenge ? "Back to sign in" : mode === "login" ? "First time here? Initialize admin" : "Back to sign in"}
          </button>
        )}
        <p className="admin-login-security"><ShieldCheck size={16} aria-hidden="true" /> Protected admin session</p>
      </section>
    </main>
  );
}
