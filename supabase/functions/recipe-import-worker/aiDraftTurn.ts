// Developer: gengyun
// Purpose: Validate an offline, evidence-grounded AI draft turn without saving or calling a live provider.

interface DraftField {
  raw_value?: string | null;
  evidence_ids?: string[];
  user_confirmed: boolean;
}
interface Context {
  ownerID: string;
  currentRevision: string;
  status: "ready" | "needs_review";
  fields: Record<string, DraftField>;
  evidence: Array<{ id: string; excerpt: string }>;
  reviewFields: string[];
}
interface Request {
  ownerID: string;
  expectedRevision: string;
  requestID: string;
  message: string;
}
interface ProviderInput {
  fields: Record<string, { raw_value: string | null; evidence_ids: string[] }>;
  evidence: Array<{ id: string; excerpt: string }>;
  reviewFields: string[];
  message: string;
  maxTotalTokens: number;
  signal: AbortSignal;
}
type Result = {
  status: "disabled" | "no_review_needed" | "proposal" | "rejected" | "unavailable";
  code?: string;
  ownerID?: string;
  revision?: string;
  requestID?: string;
  origin?: "AI_suggested";
  requiresApproval?: true;
  questions?: unknown[];
  suggestions?: unknown[];
};
type Provider = (input: ProviderInput) => Promise<unknown>;

const object = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const text = (value: unknown, max: number): value is string =>
  typeof value === "string" && value.trim().length > 0 && [...value].length <= max;
const bytes = (value: unknown) => {
  try {
    return new TextEncoder().encode(JSON.stringify(value)).length;
  } catch {
    return Infinity;
  }
};
const allowedPath = (path: string) => /^(title|servings|ingredients\[(?:[0-9]|[1-9][0-9])\]\.(name|raw_text|amount)|steps\[(?:[0-9]|[1-9][0-9])\]\.instruction)$/.test(path);
const group = (path: string) => path.split(/[\[.]/, 1)[0];
const reviewPath = (path: string) => allowedPath(path) || ["ingredients", "steps"].includes(path);
const onlyKeys = (value: Record<string, unknown>, keys: string[]) =>
  Object.keys(value).every((key) => keys.includes(key));
const rejected = (code: string): Result => ({ status: "rejected", code });

function prepare(request: unknown, context: unknown): { input: Omit<ProviderInput, "signal">; fingerprint: string } | Result {
  if (!object(request) || !onlyKeys(request, ["ownerID", "expectedRevision", "requestID", "message"]) ||
    !text(request.ownerID, 128) || !text(request.expectedRevision, 128) ||
    !text(request.requestID, 128) || typeof request.message !== "string" || [...request.message].length > 2000 ||
    !object(context) || !text(context.ownerID, 128) || !text(context.currentRevision, 128) ||
    (context.status !== "ready" && context.status !== "needs_review") ||
    !object(context.fields) || Object.keys(context.fields).length > 100 ||
    !Array.isArray(context.evidence) || context.evidence.length > 60 ||
    !Array.isArray(context.reviewFields) || context.reviewFields.length > 100) {
    return rejected("INVALID_INPUT");
  }
  if (request.ownerID !== context.ownerID) return rejected("OWNER_MISMATCH");
  if (request.expectedRevision !== context.currentRevision) return rejected("STALE_REVISION");
  const evidence: Array<{ id: string; excerpt: string }> = [];
  const evidenceIDs = new Set<string>();
  let total = 0;
  for (const item of context.evidence) {
    if (!object(item) || !text(item.id, 128) || !text(item.excerpt, 1500) || evidenceIDs.has(item.id)) {
      return rejected("INVALID_EVIDENCE");
    }
    total += [...item.excerpt].length;
    evidenceIDs.add(item.id);
    evidence.push({ id: item.id, excerpt: item.excerpt });
  }
  if (total > 20000) return rejected("INPUT_BUDGET");
  // Unsupported review flags (e.g. recipe_selection) are not AI-editable fields.
  if (!context.reviewFields.every((path) => text(path, 128))) return rejected("INVALID_REVIEW_PATH");
  const reviewFields = [...new Set(context.reviewFields as string[])].filter(reviewPath);
  const fields: ProviderInput["fields"] = {};
  for (const [path, value] of Object.entries(context.fields)) {
    if (!allowedPath(path)) continue; // Never forward notes, source, timers or other private fields.
    if (!object(value) || typeof value.user_confirmed !== "boolean" ||
      (value.raw_value != null && !text(value.raw_value, 1500)) ||
      (value.evidence_ids !== undefined && (!Array.isArray(value.evidence_ids) ||
        value.evidence_ids.length > 60 || !value.evidence_ids.every((id) => typeof id === "string" && evidenceIDs.has(id))))) {
      return rejected("INVALID_FIELD");
    }
    if (value.user_confirmed) continue;
    if (reviewFields.some((review) => review === path || review === group(path))) {
      fields[path] = { raw_value: value.raw_value as string | null ?? null, evidence_ids: [...(value.evidence_ids as string[] ?? [])] };
    }
  }
  const actionable = reviewFields.filter((path) => {
    const field = (context.fields as Record<string, unknown>)[path];
    if (object(field) && field.user_confirmed === true) return false;
    if (["ingredients", "steps"].includes(path)) {
      const known = Object.keys(context.fields as object).filter((key) => allowedPath(key) && group(key) === path);
      return known.length === 0 || known.some((key) => key in fields);
    }
    return true;
  });
  if (context.status === "ready" || actionable.length === 0) return { status: "no_review_needed" };
  const input = { fields, evidence, reviewFields: actionable, message: request.message, maxTotalTokens: 4096 };
  if (bytes(input) > 32768) return rejected("INPUT_BUDGET");
  // Include confirmed field changes in replay identity, even though they never go to the provider.
  const fingerprint = JSON.stringify({ request, input, confirmed: Object.entries(context.fields)
    .filter(([path, value]) => allowedPath(path) && object(value) && value.user_confirmed === true)
    .map(([path]) => path) });
  return { input, fingerprint };
}

function validate(output: unknown, input: Omit<ProviderInput, "signal">): Result {
  if (!object(output) || !onlyKeys(output, ["questions", "suggestions", "usage"]) ||
    !Array.isArray(output.questions) || output.questions.length > 3 ||
    !Array.isArray(output.suggestions) || output.suggestions.length > 20 ||
    !object(output.usage) || !onlyKeys(output.usage, ["totalTokens"]) ||
    !Number.isSafeInteger(output.usage.totalTokens) || (output.usage.totalTokens as number) < 0 ||
    (output.usage.totalTokens as number) > 4096 || bytes(output) > 32768) {
    return rejected("INVALID_PROVIDER_OUTPUT");
  }
  const evidence = new Map(input.evidence.map((item) => [item.id, item.excerpt]));
  const paths = new Set<string>();
  const validReference = (item: Record<string, unknown>, question: boolean) => {
    if (!text(item.path, 128) || !(question ? reviewPath(item.path) : allowedPath(item.path)) ||
      !input.reviewFields.some((path) => path === item.path || (path === group(item.path as string) && (item.path as string) in input.fields)) ||
      !Array.isArray(item.evidence_ids) || item.evidence_ids.length === 0 || item.evidence_ids.length > 60 ||
      new Set(item.evidence_ids).size !== item.evidence_ids.length ||
      !item.evidence_ids.every((id) => typeof id === "string" && evidence.has(id))) return false;
    return true;
  };
  for (const item of output.questions) {
    if (!object(item) || !onlyKeys(item, ["path", "question", "evidence_ids"]) ||
      !validReference(item, true) || !text(item.question, 300) || paths.has(`q:${item.path}`)) {
      return rejected("INVALID_PROVIDER_OUTPUT");
    }
    paths.add(`q:${item.path}`);
  }
  for (const item of output.suggestions) {
    if (!object(item) || !onlyKeys(item, ["path", "raw_value", "evidence_ids", "reason"]) ||
      !validReference(item, false) || !text(item.raw_value, 1500) || !text(item.reason, 500) || paths.has(`s:${item.path}`) ||
      !(item.evidence_ids as string[]).some((id) => evidence.get(id)!.includes(item.raw_value as string))) {
      return rejected("INVALID_PROVIDER_OUTPUT");
    }
    paths.add(`s:${item.path}`);
  }
  return { status: "proposal", origin: "AI_suggested", requiresApproval: true,
    questions: structuredClone(output.questions), suggestions: structuredClone(output.suggestions) };
}

/** No route, persistence, credentials or live provider. The caller remains responsible for auth and eventual CAS. */
export function createAIDraftTurnService(options: { enabled?: boolean; provider?: Provider; timeoutMs?: number } = {}) {
  const { enabled = false, provider, timeoutMs = 5000 } = options;
  // ponytail: bounded process-local replay only; persistent multi-worker idempotency belongs to a future approved caller.
  const requests = new Map<string, { fingerprint: string; result: Promise<Result> }>();
  return {
    async generateTurn(request: Request, context: Context): Promise<Result> {
      if (enabled !== true) return { status: "disabled" };
      if (typeof provider !== "function" || !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 10000) {
        return rejected("INVALID_CONFIGURATION");
      }
      const prepared = prepare(request, context);
      if (!("input" in prepared)) return prepared;
      const key = JSON.stringify([request.ownerID, request.requestID]);
      const previous = requests.get(key);
      if (previous) {
        if (previous.fingerprint !== prepared.fingerprint) return rejected("REQUEST_CONFLICT");
        const result = await previous.result;
        const current = prepare(request, context);
        if (!("fingerprint" in current) || current.fingerprint !== prepared.fingerprint) return rejected("STALE_REVISION");
        return structuredClone(result);
      }
      if (requests.size >= 32) return rejected("REQUEST_CAPACITY");
      const requestID = request.requestID;
      const ownerID = context.ownerID;
      const revision = context.currentRevision;
      const controller = new AbortController();
      let timer: ReturnType<typeof setTimeout>;
      const timeout = new Promise<Result>((resolve) => {
        timer = setTimeout(() => {
          controller.abort();
          resolve({ status: "unavailable", code: "PROVIDER_TIMEOUT" });
        }, timeoutMs);
      });
      // Microtask scheduling installs the replay entry before any provider code executes.
      const operation = Promise.resolve().then(async () => {
        try {
          const output = await provider({ ...structuredClone(prepared.input), signal: controller.signal });
          if (controller.signal.aborted) return { status: "unavailable", code: "PROVIDER_TIMEOUT" } as Result;
          const current = prepare(request, context);
          if (context.ownerID !== ownerID || context.currentRevision !== revision ||
            !("fingerprint" in current) || current.fingerprint !== prepared.fingerprint) return rejected("STALE_REVISION");
          const result = validate(output, prepared.input);
          return result.status === "proposal" ? { ...result, ownerID, revision, requestID } : result;
        } catch {
          return { status: "unavailable", code: "PROVIDER_UNAVAILABLE" } as Result;
        }
      });
      const result = Promise.race([operation, timeout]).then((value) => {
        clearTimeout(timer);
        if (value.status !== "proposal") requests.delete(key);
        return value;
      });
      requests.set(key, { fingerprint: prepared.fingerprint, result });
      return structuredClone(await result);
    },
  };
}
