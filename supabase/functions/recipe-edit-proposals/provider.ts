// Developer: gengyun
// Purpose: Bounded OpenAI-compatible recipe edit provider. It only emits the three value-replacement
// change paths and validates model output before it reaches the handler. No default network access.

import {
  type EditChange,
  type EditIntent,
  isEditIntent,
  validEditChanges,
  validReasons,
  validWarnings,
} from "./editSchema.ts";

interface EditProviderInput {
  intent: EditIntent;
  recipe: EditRecipeSnapshot;
  supplement: string | null;
  signal: AbortSignal;
}

export interface EditRecipeSnapshot {
  id: string;
  ingredients: Array<{ id: string; name: string; amount: string }>;
  steps: Array<{ id: string; instruction: string }>;
}

export interface EditProposalResult {
  needsManualEdit: boolean;
  changes: EditChange[];
  reasons: string[];
  warnings: string[];
}

interface Route {
  route_key: string;
  primary_model_id: string | null;
  enabled: boolean;
  timeout_ms: number;
  max_retries: number;
  max_output_tokens: number | null;
  temperature: number | null;
}

interface ModelRow {
  id: string;
  provider_id: string;
  upstream_model_id: string;
  enabled: boolean;
}

interface ProviderRow {
  id: string;
  name: string;
  base_url: string;
  secret_ref: string;
  enabled: boolean;
}

interface EditProviderOptions {
  enabled?: boolean;
  route: Route;
  model: ModelRow;
  provider: ProviderRow;
  resolveSecret: (reference: string) => Promise<string>;
  transport: (
    request: Request,
    policy: { signal: AbortSignal; maxResponseBytes: number },
  ) => Promise<Response>;
}

const MAX_RESPONSE_BYTES = 65536;
const MAX_REQUEST_BYTES = 32768;
const encoder = new TextEncoder();

type Code =
  | "EDIT_PROVIDER_DISABLED"
  | "EDIT_PROVIDER_INPUT"
  | "EDIT_PROVIDER_RESPONSE"
  | "EDIT_PROVIDER_OUTPUT"
  | "EDIT_PROVIDER_BUDGET"
  | "EDIT_PROVIDER_ABORTED";

function fail(code: Code): never {
  throw new Error(code);
}

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function text(value: unknown, min: number, max: number): value is string {
  return typeof value === "string" && value.length >= min &&
    value.length <= max;
}

function integer(value: unknown, min: number, max: number): value is number {
  return Number.isSafeInteger(value) && (value as number) >= min &&
    (value as number) <= max;
}

function checkAbort(signal: AbortSignal) {
  if (signal.aborted) fail("EDIT_PROVIDER_ABORTED");
}

const discardBody = (response: Response) => {
  void response.body?.cancel().catch(() => {});
};

function wait<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) return Promise.reject(new Error("EDIT_PROVIDER_ABORTED"));
  const { promise: result, resolve, reject } = Promise.withResolvers<T>();
  const onAbort = () => reject(new Error("EDIT_PROVIDER_ABORTED"));
  signal.addEventListener("abort", onAbort, { once: true });
  promise.then(
    (value) => {
      signal.removeEventListener("abort", onAbort);
      resolve(value);
    },
    (error) => {
      signal.removeEventListener("abort", onAbort);
      reject(error);
    },
  );
  return result;
}

async function readJSON(
  response: Response,
  signal: AbortSignal,
): Promise<unknown> {
  if (
    response.redirected || response.status < 200 || response.status >= 300 ||
    !/^application\/json(?:\s*;|$)/i.test(
      response.headers.get("content-type") ?? "",
    )
  ) {
    discardBody(response);
    fail("EDIT_PROVIDER_RESPONSE");
  }
  const declared = response.headers.get("content-length");
  if (
    declared !== null &&
    (!/^\d+$/.test(declared) || Number(declared) > MAX_RESPONSE_BYTES)
  ) {
    discardBody(response);
    fail("EDIT_PROVIDER_BUDGET");
  }
  if (!response.body) fail("EDIT_PROVIDER_RESPONSE");
  const reader = response.body.getReader();
  const onAbort = () => void reader.cancel().catch(() => {});
  signal.addEventListener("abort", onAbort, { once: true });
  let total = 0;
  const chunks: Uint8Array[] = [];
  try {
    checkAbort(signal);
    for (;;) {
      const { done, value } = await wait(reader.read(), signal);
      checkAbort(signal);
      if (done) break;
      total += value.byteLength;
      if (total > MAX_RESPONSE_BYTES) fail("EDIT_PROVIDER_BUDGET");
      chunks.push(value);
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    checkAbort(signal);
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } finally {
    signal.removeEventListener("abort", onAbort);
    void reader.cancel().catch(() => {});
    try {
      reader.releaseLock();
    } catch {
      // A canceled pending read can still hold the lock.
    }
  }
}

/** Strict provider-output validation: the three change paths only, never other fields. */
export function validEditOutput(value: unknown): value is EditProposalResult {
  if (!object(value)) return false;
  if (Object.keys(value).length !== 4) return false;
  const { needsManualEdit, changes, reasons, warnings } = value;
  if (typeof needsManualEdit !== "boolean") return false;
  if (!Array.isArray(changes)) return false;
  if (needsManualEdit) {
    if (changes.length !== 0) return false;
  } else if (!validEditChanges(changes)) {
    return false;
  }
  if (!validReasons(reasons)) return false;
  if (!validWarnings(warnings)) return false;
  return true;
}

function parseEditProposal(value: unknown): EditProposalResult {
  if (!validEditOutput(value)) fail("EDIT_PROVIDER_OUTPUT");
  return value;
}

function snapshotName(snapshot: EditRecipeSnapshot): string {
  const names = snapshot.ingredients.map((item) => item.name);
  return names.length === 0 ? "Untitled recipe" : names.join(", ");
}

/**
 * This has no fetch default, config loader, secret decryption, retry, route or
 * live-provider entry point; the composition root wires trusted transport and secret resolution.
 */
export function createRecipeEditProvider(options: EditProviderOptions) {
  let configuration:
    | {
      url: string;
      model: string;
      secretRef: string;
      maxTokens: number;
      temperature: number | null;
    }
    | undefined;
  try {
    const { route, model, provider } = options;
    if (
      options.enabled === true && route.enabled === true &&
      model.enabled === true &&
      provider.enabled === true && text(route.route_key, 1, 128) &&
      text(route.primary_model_id, 1, 128) &&
      route.primary_model_id === model.id &&
      text(provider.id, 1, 128) && model.provider_id === provider.id &&
      integer(route.timeout_ms, 1000, 300000) &&
      integer(route.max_retries, 0, 3) &&
      integer(route.max_output_tokens, 1, 4096) &&
      (route.temperature === null ||
        (typeof route.temperature === "number" &&
          Number.isFinite(route.temperature) &&
          route.temperature >= 0 && route.temperature <= 2)) &&
      text(provider.secret_ref, 1, 512) &&
      typeof options.resolveSecret === "function" &&
      typeof options.transport === "function"
    ) {
      const parsed = new URL(provider.base_url);
      if (parsed.protocol === "https:") {
        configuration = {
          url: `${provider.base_url.replace(/\/$/, "")}/chat/completions`,
          model: model.upstream_model_id,
          secretRef: provider.secret_ref,
          maxTokens: route.max_output_tokens,
          temperature: route.temperature,
        };
      }
    }
  } catch {
    // Misconfigured server snapshots remain disabled without resolving any secret.
  }

  return async (input: EditProviderInput): Promise<EditProposalResult> => {
    const config = configuration;
    if (!config) fail("EDIT_PROVIDER_DISABLED");
    if (
      !input || !(input.signal instanceof AbortSignal) ||
      !isEditIntent(input.intent) || !object(input.recipe)
    ) {
      fail("EDIT_PROVIDER_INPUT");
    }
    checkAbort(input.signal);
    const { recipe } = input;
    if (
      !text(recipe.id, 1, 128) || !Array.isArray(recipe.ingredients) ||
      !Array.isArray(recipe.steps) ||
      recipe.ingredients.length > 200 || recipe.steps.length > 200
    ) {
      fail("EDIT_PROVIDER_INPUT");
    }
    if (input.supplement !== null && !text(input.supplement, 1, 500)) {
      fail("EDIT_PROVIDER_INPUT");
    }
    const system = [
      "You propose bounded, reviewable edits to a private recipe.",
      "You may only emit exactly three change kinds, keyed by a stable lowercase UUID id:",
      "ingredient:<id>:name, ingredient:<id>:amount, step:<id>:instruction.",
      "Never add/remove ingredients or steps, never reorder, and never change title, summary,",
      "servings, timers, temperatures, or nutrition.",
      "When substituting an ingredient, also update the step instructions that reference it.",
      "Never invent a precise amount when the source has none; keep vague amounts unchanged.",
      "Dietary intents are suggestions only and must not promise allergy or medical safety.",
      "If the requested edit cannot be expressed within those three kinds, set needs_manual_edit to true",
      "with an empty changes array and explain why in reasons.",
      "Respond with JSON only: {needs_manual_edit, changes, reasons, warnings}.",
    ].join(" ");
    const user = JSON.stringify({
      intent: input.intent,
      recipe,
      supplement: input.supplement,
    });
    const payload = JSON.stringify({ system, user });
    if (encoder.encode(payload).length > MAX_REQUEST_BYTES) {
      fail("EDIT_PROVIDER_BUDGET");
    }
    let body: string;
    try {
      body = JSON.stringify({
        model: config.model,
        stream: false,
        max_tokens: config.maxTokens,
        ...(config.temperature === null
          ? {}
          : { temperature: config.temperature }),
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
      });
      if (encoder.encode(body).length > MAX_REQUEST_BYTES) {
        fail("EDIT_PROVIDER_BUDGET");
      }
    } catch {
      fail("EDIT_PROVIDER_BUDGET");
    }
    const secret = config.secretRef
      ? await options.resolveSecret(config.secretRef)
      : "";
    const request = new Request(config.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${secret}`,
      },
      body,
    });
    const response = await wait(
      options.transport(request, {
        signal: input.signal,
        maxResponseBytes: MAX_RESPONSE_BYTES,
      }),
      input.signal,
    );
    const envelope = await readJSON(response, input.signal);
    const content = extractMessageContent(envelope);
    return parseEditProposal(JSON.parse(content));
  };
}

function extractMessageContent(envelope: unknown): string {
  if (
    !object(envelope) || !Array.isArray(envelope.choices) ||
    envelope.choices.length === 0
  ) {
    fail("EDIT_PROVIDER_OUTPUT");
  }
  const first = envelope.choices[0];
  if (!object(first) || !object(first.message)) fail("EDIT_PROVIDER_OUTPUT");
  const content = first.message.content;
  if (typeof content !== "string" || content.trim().length === 0) {
    fail("EDIT_PROVIDER_OUTPUT");
  }
  return content;
}
