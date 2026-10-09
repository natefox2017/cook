// Developer: gengyun
// Purpose: Verify safe provider mapping and AI usage aggregation.

import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  buildUsageResponse,
  type ModelRow,
  parseProviderInput,
  parseUsageRange,
  type ProviderRow,
  providerView,
  type UsageEvent,
} from "./model.ts";

Deno.test("provider response reports key presence without exposing its reference", () => {
  const provider: ProviderRow = {
    id: "provider-1",
    name: "Example",
    base_url: "https://example.com/v1",
    secret_ref: "opaque-secret-ref",
    enabled: true,
    updated_at: "2026-10-09T00:00:00Z",
  };
  const model: ModelRow = {
    id: "model-1",
    provider_id: provider.id,
    upstream_model_id: "model-x",
    display_name: "Model X",
    enabled: true,
    created_at: "2026-10-01T00:00:00Z",
  };

  const view = providerView(provider, [model]);
  assertEquals(view.apiKeyConfigured, true);
  assertEquals(view.model, "model-x");
  assertEquals(JSON.stringify(view).includes("opaque-secret-ref"), false);
});

Deno.test("provider input rejects credentials and unsupported URL parts", () => {
  assertThrows(() =>
    parseProviderInput({
      name: "Example",
      baseUrl: "https://user:password@example.com",
      model: "model-x",
      active: true,
    })
  );
});

Deno.test("usage range accepts only the current client contract", () => {
  assertEquals(parseUsageRange(null), "7d");
  assertEquals(parseUsageRange("30d"), "30d");
  assertThrows(() => parseUsageRange("365d"));
});

Deno.test("usage aggregation preserves unknown cached-token telemetry", () => {
  const events: UsageEvent[] = [{
    provider_id: "provider-1",
    model_id: "model-1",
    final_model_id: null,
    status: "success",
    latency_ms: 120,
    input_tokens: 10,
    output_tokens: 5,
    created_at: "2026-10-09T12:00:00Z",
  }];
  const response = buildUsageResponse(
    events,
    new Map([["provider-1", "Example"]]),
    new Map([[
      "model-1",
      {
        id: "model-1",
        provider_id: "provider-1",
        upstream_model_id: "model-x",
      },
    ]]),
  );

  assertEquals(response.totals, {
    requests: 1,
    inputTokens: 10,
    outputTokens: 5,
    totalTokens: 15,
    cachedInputTokens: null,
    averageLatencyMs: 120,
  });
  assertEquals(response.series[0].totalTokens, 15);
  assertEquals(response.byModel[0].provider, "Example");
});

const cacheEvent: UsageEvent = {
  provider_id: null,
  model_id: null,
  final_model_id: null,
  status: "success",
  latency_ms: null,
  input_tokens: 20,
  output_tokens: 5,
  created_at: "2026-10-09T12:00:00Z",
};

Deno.test("cached-input totals sum reported counts without adding to input tokens", () => {
  const response = buildUsageResponse(
    [
      { ...cacheEvent, cache_read_input_tokens: 7 },
      { ...cacheEvent, cache_read_input_tokens: 13 },
      { ...cacheEvent, cache_read_input_tokens: null },
    ],
    new Map(),
    new Map(),
  );
  assertEquals(response.totals.cachedInputTokens, 20);
  assertEquals(response.totals.inputTokens, 60);
  assertEquals(response.totals.totalTokens, 75);
});

Deno.test("cached-input totals remain unknown when no event reports a value", () => {
  const response = buildUsageResponse(
    [
      cacheEvent,
      { ...cacheEvent, cache_read_input_tokens: null },
    ],
    new Map(),
    new Map(),
  );
  assertEquals(response.totals.cachedInputTokens, null);
});

Deno.test("reported zero cached input remains zero rather than unknown", () => {
  const response = buildUsageResponse(
    [
      cacheEvent,
      { ...cacheEvent, cache_read_input_tokens: 0 },
    ],
    new Map(),
    new Map(),
  );
  assertEquals(response.totals.cachedInputTokens, 0);
});
