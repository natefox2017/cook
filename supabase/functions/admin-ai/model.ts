import { AppError } from "../_shared/errors.ts";

export type UsageRange = "7d" | "30d" | "90d";

export type ProviderRow = {
  id: string;
  name: string;
  base_url: string;
  secret_ref: string | null;
  enabled: boolean;
  updated_at: string;
};

export type ModelRow = {
  id: string;
  provider_id: string;
  upstream_model_id: string;
  display_name: string;
  enabled: boolean;
  created_at: string;
};

export type ProviderInput = {
  name: string;
  baseUrl: string;
  model: string;
  apiKey: string;
  active: boolean;
};

export type UsageEvent = {
  provider_id: string | null;
  model_id: string | null;
  final_model_id: string | null;
  status: string;
  latency_ms: number | null;
  input_tokens: number | null;
  output_tokens: number | null;
  created_at: string;
};

export type ModelLabel = {
  id: string;
  provider_id: string;
  upstream_model_id: string;
};

export function parseUsageRange(value: string | null): UsageRange {
  if (value === null || value === "7d") return "7d";
  if (value === "30d" || value === "90d") return value;
  throw new AppError(
    "validation_error",
    "Usage range must be 7d, 30d, or 90d",
    400,
  );
}

export function parseProviderInput(
  value: Record<string, unknown>,
): ProviderInput {
  const name = typeof value.name === "string" ? value.name.trim() : "";
  const baseUrl = typeof value.baseUrl === "string" ? value.baseUrl.trim() : "";
  const model = typeof value.model === "string" ? value.model.trim() : "";
  const apiKey = typeof value.apiKey === "string" ? value.apiKey : "";
  const active = value.active === true;

  if (!name || name.length > 120 || !model || model.length > 256) {
    throw new AppError(
      "validation_error",
      "Provider name and model are required",
      400,
    );
  }
  if (apiKey.length > 8192) {
    throw new AppError(
      "validation_error",
      "Provider key exceeds the supported size",
      400,
    );
  }
  if (baseUrl.length > 2048) {
    throw new AppError(
      "validation_error",
      "Provider URL exceeds the supported size",
      400,
    );
  }

  let url: URL;
  try {
    url = new URL(baseUrl);
  } catch {
    throw new AppError(
      "validation_error",
      "Provider URL must be an absolute HTTP or HTTPS URL",
      400,
    );
  }
  if (
    (url.protocol !== "https:" && url.protocol !== "http:") ||
    url.username || url.password || url.search || url.hash
  ) {
    throw new AppError(
      "validation_error",
      "Provider URL must use HTTP or HTTPS without credentials, query, or fragment",
      400,
    );
  }

  return {
    name,
    baseUrl: url.toString().replace(/\/$/, ""),
    model,
    apiKey,
    active,
  };
}

export function providerView(
  provider: ProviderRow,
  models: readonly ModelRow[],
): {
  id: string;
  name: string;
  baseUrl: string;
  model: string;
  active: boolean;
  apiKeyConfigured: boolean;
  updatedAt: string;
} {
  const model =
    [...models].sort((left, right) =>
      Number(right.enabled) - Number(left.enabled) ||
      left.created_at.localeCompare(right.created_at) ||
      left.id.localeCompare(right.id)
    )[0];

  return {
    id: provider.id,
    name: provider.name,
    baseUrl: provider.base_url,
    model: model?.upstream_model_id ?? "",
    active: provider.enabled,
    apiKeyConfigured: provider.secret_ref !== null,
    updatedAt: provider.updated_at,
  };
}

export function buildUsageResponse(
  events: readonly UsageEvent[],
  providers: ReadonlyMap<string, string>,
  models: ReadonlyMap<string, ModelLabel>,
) {
  let inputTotal = 0;
  let inputCount = 0;
  let outputTotal = 0;
  let outputCount = 0;
  let latencyTotal = 0;
  let latencyCount = 0;
  const byDate = new Map<string, {
    requests: number;
    inputTokens: number;
    outputTokens: number;
  }>();
  const byModel = new Map<string, {
    provider: string;
    model: string;
    requests: number;
    totalTokens: number;
  }>();

  for (const event of events) {
    const date = new Date(event.created_at).toISOString().slice(0, 10);
    const daily = byDate.get(date) ?? {
      requests: 0,
      inputTokens: 0,
      outputTokens: 0,
    };
    daily.requests += 1;
    daily.inputTokens += event.input_tokens ?? 0;
    daily.outputTokens += event.output_tokens ?? 0;
    byDate.set(date, daily);

    if (event.input_tokens !== null) {
      inputTotal += event.input_tokens;
      inputCount += 1;
    }
    if (event.output_tokens !== null) {
      outputTotal += event.output_tokens;
      outputCount += 1;
    }
    if (event.latency_ms !== null) {
      latencyTotal += event.latency_ms;
      latencyCount += 1;
    }

    const modelId = event.final_model_id ?? event.model_id;
    const model = modelId ? models.get(modelId) : undefined;
    const providerId = model?.provider_id ?? event.provider_id;
    const providerName = providerId ? providers.get(providerId) : undefined;
    const modelName = model?.upstream_model_id;
    const providerLabel = providerName ?? "Unknown provider";
    const modelLabel = modelName ?? "Unknown model";
    const key = `${providerLabel}\u0000${modelLabel}`;
    const summary = byModel.get(key) ?? {
      provider: providerLabel,
      model: modelLabel,
      requests: 0,
      totalTokens: 0,
    };
    summary.requests += 1;
    summary.totalTokens += (event.input_tokens ?? 0) +
      (event.output_tokens ?? 0);
    byModel.set(key, summary);
  }

  const series = [...byDate.entries()].sort(([left], [right]) =>
    left.localeCompare(right)
  ).map(([date, values]) => ({
    date,
    ...values,
    totalTokens: values.inputTokens + values.outputTokens,
  }));
  const inputTokens = inputCount ? inputTotal : null;
  const outputTokens = outputCount ? outputTotal : null;

  return {
    totals: {
      requests: events.length,
      inputTokens,
      outputTokens,
      totalTokens: inputTokens === null || outputTokens === null
        ? null
        : inputTokens + outputTokens,
      cachedInputTokens: null,
      averageLatencyMs: latencyCount ? latencyTotal / latencyCount : null,
    },
    series,
    byModel: [...byModel.values()].sort((left, right) =>
      right.requests - left.requests ||
      left.provider.localeCompare(right.provider) ||
      left.model.localeCompare(right.model)
    ),
  };
}
