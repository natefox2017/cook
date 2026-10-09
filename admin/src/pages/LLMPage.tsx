// Developer: gengyun
// Purpose: Manage OpenAI-compatible model providers and inspect token usage.

import { useEffect, useState, type FormEvent } from "react";
import {
  Activity,
  ArrowDownToLine,
  ArrowUpToLine,
  AlertCircle,
  Check,
  CircleHelp,
  Cpu,
  KeyRound,
  LoaderCircle,
  Pencil,
  Plus,
  RefreshCw,
  Server,
  Eye,
  EyeOff,
  Trash2,
  Zap,
} from "lucide-react";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { adminApi, handleExpiredSession } from "../api";
import { AdminSelect } from "../components/AdminSelect";
import type { AdminRole, LLMProvider, LLMProviderInput, LLMUsage, LLMUsageRange } from "../types";
import "./LLMPage.css";

type LLMPageProps = {
  token: string;
  role: AdminRole;
  onAuthExpired: () => void;
};

type ProviderDraft = LLMProviderInput;

const emptyDraft: ProviderDraft = {
  name: "",
  baseUrl: "",
  model: "",
  apiKey: "",
  active: true,
};

const ranges: Array<{ value: LLMUsageRange; label: string }> = [
  { value: "7d", label: "7 days" },
  { value: "30d", label: "30 days" },
  { value: "90d", label: "90 days" },
];

function formatNumber(value: number) {
  return new Intl.NumberFormat("en-US", { notation: value >= 100_000 ? "compact" : "standard", maximumFractionDigits: 1 }).format(value);
}

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? value
    : new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(date);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function numberFrom(record: Record<string, unknown>, ...keys: string[]): number | null {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "number" && Number.isFinite(value)) return value;
  }
  return null;
}

function normalizeUsage(value: unknown): LLMUsage | null {
  const payload = asRecord(value);
  if (!payload) return null;

  const data = asRecord(payload.data) ?? asRecord(payload.usage) ?? payload;
  const sourceTotals = asRecord(data.totals) ?? asRecord(data.summary);
  const events = Array.isArray(data.events)
    ? data.events.map(asRecord).filter((event): event is Record<string, unknown> => event !== null)
    : [];

  const eventTotals = events.reduce<{
    requests: number;
    inputTokens: number;
    inputTokenCount: number;
    outputTokens: number;
    outputTokenCount: number;
    cachedInputTokens: number;
    cachedTokenCount: number;
    latencyTotal: number;
    latencyCount: number;
  }>((totals, event) => ({
    requests: totals.requests + 1,
    inputTokens: totals.inputTokens + (numberFrom(event, "inputTokens", "input_tokens") ?? 0),
    inputTokenCount: totals.inputTokenCount + (numberFrom(event, "inputTokens", "input_tokens") === null ? 0 : 1),
    outputTokens: totals.outputTokens + (numberFrom(event, "outputTokens", "output_tokens") ?? 0),
    outputTokenCount: totals.outputTokenCount + (numberFrom(event, "outputTokens", "output_tokens") === null ? 0 : 1),
    cachedInputTokens: totals.cachedInputTokens + (numberFrom(event, "cachedInputTokens", "cached_input_tokens", "cacheReadInputTokens", "cache_read_input_tokens") ?? 0),
    cachedTokenCount: totals.cachedTokenCount + (numberFrom(event, "cachedInputTokens", "cached_input_tokens", "cacheReadInputTokens", "cache_read_input_tokens") === null ? 0 : 1),
    latencyTotal: totals.latencyTotal + (numberFrom(event, "latencyMs", "latency_ms") ?? 0),
    latencyCount: totals.latencyCount + (numberFrom(event, "latencyMs", "latency_ms") === null ? 0 : 1),
  }), { requests: 0, inputTokens: 0, inputTokenCount: 0, outputTokens: 0, outputTokenCount: 0, cachedInputTokens: 0, cachedTokenCount: 0, latencyTotal: 0, latencyCount: 0 });

  const requests = numberFrom(sourceTotals ?? {}, "requests", "requestCount", "request_count")
    ?? (events.length ? eventTotals.requests : null);
  const inputTokens = numberFrom(sourceTotals ?? {}, "inputTokens", "input_tokens")
    ?? (eventTotals.inputTokenCount === events.length && events.length ? eventTotals.inputTokens : null);
  const outputTokens = numberFrom(sourceTotals ?? {}, "outputTokens", "output_tokens")
    ?? (eventTotals.outputTokenCount === events.length && events.length ? eventTotals.outputTokens : null);

  const series = Array.isArray(data.series) ? data.series.filter((item) => {
    const row = asRecord(item);
    return row && typeof row.date === "string" &&
      [row.requests, row.inputTokens, row.outputTokens, row.totalTokens].every(Number.isFinite);
  }) : [];
  const byModel = Array.isArray(data.byModel) ? data.byModel.filter((item) => {
    const row = asRecord(item);
    return row && typeof row.provider === "string" && typeof row.model === "string" &&
      [row.requests, row.totalTokens].every(Number.isFinite);
  }) : [];
  const cachedInputTokens = numberFrom(sourceTotals ?? {}, "cachedInputTokens", "cached_input_tokens", "cacheReadInputTokens", "cache_read_input_tokens")
    ?? (eventTotals.cachedTokenCount === events.length && events.length ? eventTotals.cachedInputTokens : null);
  const averageLatencyMs = numberFrom(sourceTotals ?? {}, "averageLatencyMs", "avgLatencyMs", "average_latency_ms", "avg_latency_ms")
    ?? (eventTotals.latencyCount === events.length && events.length ? eventTotals.latencyTotal / eventTotals.latencyCount : null);

  return {
    totals: {
      requests,
      inputTokens,
      outputTokens,
      totalTokens: numberFrom(sourceTotals ?? {}, "totalTokens", "total_tokens")
        ?? (inputTokens !== null && outputTokens !== null ? inputTokens + outputTokens : null),
      cachedInputTokens,
      averageLatencyMs,
    },
    series: series as LLMUsage["series"],
    byModel: byModel as LLMUsage["byModel"],
  };
}

function ErrorNotice({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="llm-error" role="alert">
      <AlertCircle size={17} aria-hidden="true" />
      <span>{message}</span>
      <button type="button" className="llm-link-button" onClick={onRetry}>Try again</button>
    </div>
  );
}

function Metric({ label, value, icon: Icon }: { label: string; value: string; icon: typeof Activity }) {
  return (
    <article className="llm-metric card">
      <div className="llm-metric-top"><span>{label}</span><span className="llm-metric-icon"><Icon size={17} aria-hidden="true" /></span></div>
      <strong>{value}</strong>
    </article>
  );
}

export function LLMPage({ token, role, onAuthExpired }: LLMPageProps) {
  const canManage = role === "owner" || role === "admin";
  const [providers, setProviders] = useState<LLMProvider[]>([]);
  const [usage, setUsage] = useState<LLMUsage | null>(null);
  const [range, setRange] = useState<LLMUsageRange>("7d");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [editor, setEditor] = useState<LLMProvider | "new" | null>(null);
  const [draft, setDraft] = useState<ProviderDraft>(emptyDraft);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState("");
  const [deleting, setDeleting] = useState<LLMProvider | null>(null);
  const [deleteError, setDeleteError] = useState("");
  const [deletingProvider, setDeletingProvider] = useState(false);
  const [apiKeyVisible, setApiKeyVisible] = useState(false);
  const [testingConnection, setTestingConnection] = useState(false);
  const [connectionResult, setConnectionResult] = useState("");

  async function load() {
    setLoading(true);
    setError("");
    try {
      const [providerResponse, usageResponse] = await Promise.allSettled([
        adminApi.llmProviders(token),
        adminApi.llmUsage(token, range),
      ]);
      if (providerResponse.status === "fulfilled") {
        const providerPayload = asRecord(providerResponse.value);
        const providerData = Array.isArray(providerResponse.value)
          ? providerResponse.value
          : Array.isArray(providerPayload?.data)
          ? providerPayload.data
          : null;
        if (providerData) {
          const normalizedProviders = providerData.flatMap((item): LLMProvider[] => {
            const provider = asRecord(item);
            if (!provider || typeof provider.id !== "string" || typeof provider.name !== "string") return [];
            return [{
              id: provider.id,
              name: provider.name,
              baseUrl: typeof provider.baseUrl === "string" ? provider.baseUrl : "",
              model: typeof provider.model === "string" ? provider.model : "",
              active: provider.active === true,
              apiKeyConfigured: provider.apiKeyConfigured === true,
              updatedAt: typeof provider.updatedAt === "string" ? provider.updatedAt : "",
            }];
          });
          setProviders(normalizedProviders);
        } else {
          setError("Provider settings returned incomplete data.");
        }
      } else {
        handleExpiredSession(providerResponse.reason, onAuthExpired);
        setError(providerResponse.reason instanceof Error ? providerResponse.reason.message : "Unable to load provider settings.");
      }
      if (usageResponse.status === "fulfilled") {
        const normalizedUsage = normalizeUsage(usageResponse.value);
        setUsage(normalizedUsage);
        if (!normalizedUsage) setError("Usage data could not be read. Provider settings are still available.");
      } else {
        handleExpiredSession(usageResponse.reason, onAuthExpired);
        setUsage(null);
        setError(usageResponse.reason instanceof Error ? usageResponse.reason.message : "Unable to load usage data.");
      }
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
    // Reload only when the session or selected usage window changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, range]);

  function beginCreate() {
    setDraft({ ...emptyDraft });
    setFormError("");
    setConnectionResult("");
    setApiKeyVisible(false);
    setEditor("new");
  }

  function beginEdit(provider: LLMProvider) {
    setDraft({ name: provider.name, baseUrl: provider.baseUrl, model: provider.model, apiKey: "", active: provider.active });
    setFormError("");
    setConnectionResult("");
    setApiKeyVisible(false);
    setEditor(provider);
  }

  function closeEditor() {
    setEditor(null);
    setDraft({ ...emptyDraft });
    setApiKeyVisible(false);
    setConnectionResult("");
  }

  async function saveProvider(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFormError("");
    const currentEditor = editor;
    if (!currentEditor) return;
    const baseUrl = draft.baseUrl.trim();
    try {
      const parsed = new URL(baseUrl);
      if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
        setFormError("Use an HTTP or HTTPS API base URL.");
        return;
      }
    } catch {
      setFormError("Enter a valid HTTP or HTTPS API base URL.");
      return;
    }
    if (currentEditor === "new" && !draft.apiKey.trim()) {
      setFormError("Enter an API key for this provider.");
      return;
    }

    setSaving(true);
    try {
      await adminApi.saveLlmProvider(token, {
        name: draft.name.trim(),
        baseUrl,
        model: draft.model.trim(),
        apiKey: draft.apiKey.trim(),
        active: draft.active,
      }, currentEditor === "new" ? undefined : currentEditor.id);
      closeEditor();
      await load();
    } catch (cause) {
      handleExpiredSession(cause, onAuthExpired);
      setFormError("Unable to save provider. Check the configuration and try again.");
    } finally {
      setSaving(false);
    }
  }

  async function testConnection() {
    if (!editor) return;
    setFormError("");
    setConnectionResult("");
    const apiKey = draft.apiKey.trim();
    let providerUrl: URL;
    try {
      providerUrl = new URL(draft.baseUrl.trim());
    } catch {
      setFormError("Enter a valid HTTPS provider URL before testing.");
      return;
    }
    if (providerUrl.protocol !== "https:") {
      setFormError("Connection tests require an HTTPS provider URL. The key was not sent.");
      return;
    }
    if (!apiKey && (editor === "new" || !editor.apiKeyConfigured)) {
      setFormError("Enter an API key before testing this connection.");
      return;
    }

    setTestingConnection(true);
    try {
      const result = await adminApi.testLlmProvider(token, {
        ...(editor === "new" ? {} : { providerId: editor.id }),
        name: draft.name.trim(),
        baseUrl: providerUrl.toString(),
        model: draft.model.trim(),
        ...(apiKey ? { apiKey } : {}),
      });
      if (!result.ok) {
        setFormError("The provider could not verify the connection.");
      } else {
        setConnectionResult("Connection successful.");
      }
    } catch (cause) {
      handleExpiredSession(cause, onAuthExpired);
      setFormError("Connection test failed. Check the provider settings and try again.");
    } finally {
      setTestingConnection(false);
    }
  }

  async function confirmDelete() {
    if (!deleting) return;
    setDeletingProvider(true);
    setDeleteError("");
    try {
      await adminApi.deleteLlmProvider(token, deleting.id);
      setProviders((current) => current.filter((provider) => provider.id !== deleting.id));
      setDeleting(null);
    } catch (cause) {
      handleExpiredSession(cause, onAuthExpired);
      setDeleteError(cause instanceof Error ? cause.message : "Unable to delete provider.");
    } finally {
      setDeletingProvider(false);
    }
  }

  const hasUsage = usage !== null && (
    usage.totals.requests !== null
      ? usage.totals.requests > 0
      : usage.totals.inputTokens !== null || usage.totals.outputTokens !== null ||
        usage.series.length > 0 || usage.byModel.length > 0
  );

  return (
    <main className="llm-page">
      <header className="llm-heading page-heading-row">
        <div>
          <p className="eyebrow">OPERATIONS</p>
          <h1>Model providers</h1>
          <p className="muted">Configure OpenAI-compatible endpoints and monitor model usage.</p>
        </div>
        <div className="llm-heading-actions">
          <AdminSelect
            className="llm-range-select"
            label="Usage range"
            value={range}
            onValueChange={(value) => setRange(value as LLMUsageRange)}
            options={ranges}
          />
          <button type="button" className="button button-outline" onClick={() => void load()} disabled={loading}>
            <RefreshCw size={15} aria-hidden="true" className={loading ? "llm-spin" : ""} /> Refresh
          </button>
          {canManage && <button type="button" className="button button-primary" onClick={beginCreate}><Plus size={16} aria-hidden="true" /> Add provider</button>}
        </div>
      </header>

      {error && <ErrorNotice message={error} onRetry={() => void load()} />}

      <section className="llm-usage-section" aria-labelledby="llm-usage-title">
        <div className="llm-section-heading">
          <div><h2 id="llm-usage-title">Token usage</h2><p>Requests, tokens, and response time recorded by the model worker. Cached input is included in input tokens.</p></div>
          <span className="llm-period-pill"><Activity size={14} aria-hidden="true" /> Last {range.replace("d", " days")}</span>
        </div>
        {loading ? (
          <div className="llm-loading"><LoaderCircle size={18} className="llm-spin" aria-hidden="true" /> Loading usage…</div>
        ) : hasUsage && usage ? (
          <>
            <div className="llm-metric-grid">
              <Metric label="Requests" value={usage.totals.requests === null ? "Not reported" : formatNumber(usage.totals.requests)} icon={Zap} />
              <Metric label="Input tokens" value={usage.totals.inputTokens === null ? "Not reported" : formatNumber(usage.totals.inputTokens)} icon={ArrowDownToLine} />
              <Metric label="Output tokens" value={usage.totals.outputTokens === null ? "Not reported" : formatNumber(usage.totals.outputTokens)} icon={ArrowUpToLine} />
              <Metric label="Cached input tokens" value={usage.totals.cachedInputTokens == null ? "Not reported" : formatNumber(usage.totals.cachedInputTokens)} icon={Cpu} />
              <Metric label="Avg. response time" value={usage.totals.averageLatencyMs == null ? "Not reported" : `${formatNumber(usage.totals.averageLatencyMs)} ms`} icon={Activity} />
            </div>
            <div className="llm-usage-grid">
              <section className="llm-panel card">
                <div className="llm-panel-heading"><div><h3>Token usage over time</h3><p>Input and output tokens by day</p></div></div>
                {usage.series.length ? (
                  <div className="llm-chart">
                    <ResponsiveContainer width="100%" height="100%">
                      <AreaChart data={usage.series} margin={{ top: 10, right: 8, left: -16, bottom: 0 }}>
                        <defs>
                          <linearGradient id="llmInputFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#16803d" stopOpacity={0.18} /><stop offset="100%" stopColor="#16803d" stopOpacity={0.01} /></linearGradient>
                          <linearGradient id="llmOutputFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#75b98a" stopOpacity={0.2} /><stop offset="100%" stopColor="#75b98a" stopOpacity={0.02} /></linearGradient>
                        </defs>
                        <CartesianGrid vertical={false} stroke="#edf0ed" strokeDasharray="3 5" />
                        <XAxis dataKey="date" axisLine={false} tickLine={false} tick={{ fill: "#929b94", fontSize: 10 }} tickFormatter={formatDate} dy={8} />
                        <YAxis axisLine={false} tickLine={false} tick={{ fill: "#929b94", fontSize: 10 }} tickFormatter={(value: number) => new Intl.NumberFormat("en", { notation: "compact" }).format(value)} width={48} />
                        <Tooltip labelFormatter={(label) => formatDate(String(label))} formatter={(value, name) => [formatNumber(Number(value)), name === "inputTokens" ? "Input tokens" : "Output tokens"]} contentStyle={{ borderRadius: 9, borderColor: "#e5e9e5", fontSize: 11 }} />
                        <Area type="monotone" dataKey="inputTokens" stroke="#16803d" strokeWidth={2} fill="url(#llmInputFill)" />
                        <Area type="monotone" dataKey="outputTokens" stroke="#75b98a" strokeWidth={2} fill="url(#llmOutputFill)" />
                      </AreaChart>
                    </ResponsiveContainer>
                  </div>
                ) : <div className="llm-inline-empty">No daily usage records in this period.</div>}
                <div className="llm-chart-legend"><span><i className="llm-legend-input" /> Input tokens</span><span><i className="llm-legend-output" /> Output tokens</span></div>
              </section>
              <section className="llm-panel card">
                <div className="llm-panel-heading"><div><h3>Usage by model</h3><p>Models with recorded requests</p></div></div>
                {usage.byModel.length ? (
                  <div className="llm-model-list">
                    {usage.byModel.map((model) => (
                      <div className="llm-model-row" key={`${model.provider}-${model.model}`}>
                        <span className="llm-model-icon"><Cpu size={16} aria-hidden="true" /></span>
                        <span className="llm-model-copy"><strong>{model.model}</strong><small>{model.provider} · {formatNumber(model.requests)} requests</small></span>
                        <strong className="llm-model-tokens">{formatNumber(model.totalTokens)} <small>tokens</small></strong>
                      </div>
                    ))}
                  </div>
                ) : <div className="llm-inline-empty">No model usage records in this period.</div>}
              </section>
            </div>
          </>
        ) : (
          <div className="llm-empty card">
            <span className="llm-empty-icon"><CircleHelp size={21} aria-hidden="true" /></span>
            <strong>No token usage yet</strong>
            <span>Usage is collected when a model call is wired to the worker.</span>
          </div>
        )}
      </section>

      <section className="llm-providers-section" aria-labelledby="llm-providers-title">
        <div className="llm-section-heading">
          <div><h2 id="llm-providers-title">Providers</h2><p>OpenAI-compatible APIs available to backend model calls.</p></div>
          <span className="llm-count-pill"><Server size={14} aria-hidden="true" /> {providers.length} configured</span>
        </div>
        {loading ? (
          <div className="llm-loading"><LoaderCircle size={18} className="llm-spin" aria-hidden="true" /> Loading providers…</div>
        ) : providers.length ? (
          <div className="llm-provider-list card">
            {providers.map((provider) => (
              <article className="llm-provider-row" key={provider.id}>
                <span className="llm-provider-glyph"><Server size={18} aria-hidden="true" /></span>
                <div className="llm-provider-main">
                  <div className="llm-provider-title"><strong>{provider.name}</strong><span className={`llm-status ${provider.active ? "active" : "inactive"}`}><i />{provider.active ? "Active" : "Inactive"}</span></div>
                  <div className="llm-provider-details"><span><Cpu size={13} aria-hidden="true" /> {provider.model}</span><span className="llm-provider-url">{provider.baseUrl}</span><span className="llm-key-status">{provider.apiKeyConfigured ? <><Check size={13} aria-hidden="true" /> Key configured</> : <><KeyRound size={13} aria-hidden="true" /> No key configured</>}</span></div>
                </div>
                {canManage && <div className="llm-provider-actions"><button type="button" className="icon-button" aria-label={`Edit ${provider.name}`} title="Edit provider" onClick={() => beginEdit(provider)}><Pencil size={15} aria-hidden="true" /></button><button type="button" className="icon-button llm-danger-action" aria-label={`Delete ${provider.name}`} title="Delete provider" onClick={() => { setDeleting(provider); setDeleteError(""); }}><Trash2 size={15} aria-hidden="true" /></button></div>}
              </article>
            ))}
          </div>
        ) : (
          <div className="llm-empty card"><span className="llm-empty-icon"><Server size={21} aria-hidden="true" /></span><strong>No providers configured</strong><span>{canManage ? "Add an endpoint to make it available for backend model calls." : "A provider has not been configured yet."}</span></div>
        )}
        {!canManage && <p className="llm-readonly-note">You have read-only access to model provider settings.</p>}
      </section>

      {editor && (
        <div className="llm-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !saving) closeEditor(); }}>
          <section className="llm-dialog card" role="dialog" aria-modal="true" aria-labelledby="llm-editor-title">
            <header><span className="llm-dialog-icon"><Cpu size={18} aria-hidden="true" /></span><div><h2 id="llm-editor-title">{editor === "new" ? "Add provider" : "Edit provider"}</h2><p>Connect an OpenAI-compatible API endpoint.</p></div><button type="button" className="icon-button" aria-label="Close dialog" onClick={closeEditor} disabled={saving}>×</button></header>
            <form onSubmit={(event) => void saveProvider(event)}>
              <label className="llm-field"><span>Display name</span><input required autoFocus value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} placeholder="Production OpenAI" /></label>
              <label className="llm-field"><span>API base URL</span><input required type="url" inputMode="url" value={draft.baseUrl} onChange={(event) => setDraft({ ...draft, baseUrl: event.target.value })} placeholder="https://api.example.com/v1" /></label>
              <label className="llm-field"><span>Model name</span><input required value={draft.model} onChange={(event) => setDraft({ ...draft, model: event.target.value })} placeholder="gpt-4o-mini" /></label>
              <label className="llm-field"><span>API key <small>{editor === "new" ? "Required" : "Optional · blank keeps the saved key"}</small></span><div className="llm-key-input"><input required={editor === "new"} type={apiKeyVisible ? "text" : "password"} autoComplete="new-password" value={draft.apiKey} onChange={(event) => setDraft({ ...draft, apiKey: event.target.value })} placeholder={editor !== "new" && editor.apiKeyConfigured ? "Key configured · enter a new key to replace" : "sk-…"} /><button type="button" className="llm-key-visibility" aria-label={apiKeyVisible ? "Hide API key" : "Show API key"} aria-pressed={apiKeyVisible} onClick={() => setApiKeyVisible((visible) => !visible)}><span aria-hidden="true">{apiKeyVisible ? <EyeOff size={16} /> : <Eye size={16} />}</span></button></div></label>
              {editor !== "new" && <p className="llm-key-hint">Saved API keys are never displayed. Leave this field blank to keep the current key.</p>}
              <div className="llm-connection-row"><button type="button" className="button button-outline" onClick={() => void testConnection()} disabled={saving || testingConnection}><Zap size={15} aria-hidden="true" />{testingConnection ? "Testing…" : "Test connection"}</button>{connectionResult && <span role="status">{connectionResult}</span>}</div>
              <label className="llm-toggle"><input type="checkbox" checked={draft.active} onChange={(event) => setDraft({ ...draft, active: event.target.checked })} /><span><strong>Provider active</strong><small>Active providers can be selected for model calls.</small></span></label>
              {formError && <div className="llm-form-error" role="alert">{formError}</div>}
              <footer><button type="button" className="button button-outline" disabled={saving} onClick={closeEditor}>Cancel</button><button type="submit" className="button button-primary" disabled={saving || testingConnection}>{saving && <LoaderCircle size={15} className="llm-spin" aria-hidden="true" />}{saving ? "Saving…" : "Save provider"}</button></footer>
            </form>
          </section>
        </div>
      )}

      {deleting && (
        <div className="llm-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !deletingProvider) setDeleting(null); }}>
          <section className="llm-confirm-dialog card" role="alertdialog" aria-modal="true" aria-labelledby="llm-delete-title" aria-describedby="llm-delete-description">
            <span className="llm-delete-icon"><Trash2 size={19} aria-hidden="true" /></span>
            <h2 id="llm-delete-title">Delete {deleting.name}?</h2>
            <p id="llm-delete-description">This removes the provider configuration. This action cannot be undone.</p>
            {deleteError && <div className="llm-form-error" role="alert">{deleteError}</div>}
            <footer><button type="button" className="button button-outline" disabled={deletingProvider} onClick={() => setDeleting(null)}>Cancel</button><button type="button" className="button llm-delete-button" disabled={deletingProvider} onClick={() => void confirmDelete()}>{deletingProvider && <LoaderCircle size={15} className="llm-spin" aria-hidden="true" />}{deletingProvider ? "Deleting…" : "Delete provider"}</button></footer>
          </section>
        </div>
      )}
    </main>
  );
}

export default LLMPage;
