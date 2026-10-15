// Developer: gengyun
// Purpose: Authenticated, bounded recipe Q&A Edge Function entrypoint.

import "jsr:@supabase/functions-js@2.117.3/edge-runtime.d.ts";

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.117.3";
import { readBoundedJSONObject } from "../_shared/bounded-json.ts";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import { requireUser, createServiceClient } from "../_shared/auth.ts";
import { resolveAISecret, type AISecret } from "../_shared/ai-secret.ts";
import { createAIDraftSafeTransport } from "../recipe-import-worker/aiDraftSafeTransport.ts";
import {
  createQuestionHandler,
  validateQuestionRequest,
  type QuestionMeteringPort,
  type QuestionProviderPort,
} from "./handler.ts";
import { createInMemoryQuestionMetering } from "./questionMetering.ts";
import { createRecipeQuestionProvider } from "./questionProvider.ts";

const MAX_BODY_BYTES = 32_768;
const QUESTION_ROUTE_KEY = "recipe_question_v1";

type ServiceClient = SupabaseClient;

type SafeTransport = (
  request: Request,
  policy: { signal: AbortSignal; maxResponseBytes: number },
) => Promise<Response>;

interface RouteConfiguration {
  route: {
    route_key: string;
    primary_model_id: string | null;
    enabled: boolean;
    timeout_ms: number;
    max_retries: number;
    max_output_tokens: number | null;
    temperature: number | null;
  };
  model: {
    id: string;
    provider_id: string;
    upstream_model_id: string;
    display_name: string;
    enabled: boolean;
    created_at: string;
  };
  provider: {
    id: string;
    name: string;
    base_url: string;
    secret_ref: string | null;
    enabled: boolean;
    updated_at: string;
  };
}

export interface RecipeQuestionsDependencies {
  authenticate: typeof requireUser;
  createServiceClient: () => ServiceClient;
  loadRoute: (client: ServiceClient) => Promise<RouteConfiguration | null>;
  resolveSecret: (client: ServiceClient, reference: string) => Promise<string>;
  transport: SafeTransport;
  metering: QuestionMeteringPort;
}

async function loadQuestionRoute(client: ServiceClient): Promise<RouteConfiguration | null> {
  const { data: route, error: routeError } = await client
    .from("ai_routes")
    .select(
      "route_key,primary_model_id,enabled,timeout_ms,max_retries,max_output_tokens,temperature",
    )
    .eq("route_key", QUESTION_ROUTE_KEY)
    .eq("enabled", true)
    .single();
  if (routeError || !route) return null;
  const { data: model, error: modelError } = await client
    .from("ai_models")
    .select("id,provider_id,upstream_model_id,display_name,enabled,created_at")
    .eq("id", route.primary_model_id)
    .eq("enabled", true)
    .single();
  if (modelError || !model) return null;
  const { data: provider, error: providerError } = await client
    .from("ai_providers")
    .select("id,name,base_url,secret_ref,enabled,updated_at")
    .eq("id", model.provider_id)
    .eq("enabled", true)
    .single();
  if (providerError || !provider || typeof provider.secret_ref !== "string") return null;
  return {
    route: route as RouteConfiguration["route"],
    model: model as RouteConfiguration["model"],
    provider: provider as RouteConfiguration["provider"],
  };
}

async function resolveQuestionSecret(
  client: ServiceClient,
  reference: string,
): Promise<string> {
  const { data: secret, error } = await client
    .from("ai_secrets")
    .select("secret_ref,ciphertext,nonce,key_version")
    .eq("secret_ref", reference)
    .single();
  if (error || !secret) {
    throw new AppError("server_misconfigured", "AI secret is unavailable", 503);
  }
  return await resolveAISecret(secret as AISecret);
}

const productionDependencies: RecipeQuestionsDependencies = {
  authenticate: requireUser,
  createServiceClient,
  loadRoute: loadQuestionRoute,
  resolveSecret: resolveQuestionSecret,
  transport: createAIDraftSafeTransport(),
  metering: createInMemoryQuestionMetering(),
};

export function createRecipeQuestionsHandler(
  dependencies: RecipeQuestionsDependencies = productionDependencies,
): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    const cors = handleCors(request, "auth");
    if (cors) return cors;
    const headers = authCorsHeaders(request);
    try {
      if (request.method !== "POST") {
        throw new AppError("method_not_allowed", "POST required", 405);
      }
      const { user } = await dependencies.authenticate(request);
      const body = await readBoundedJSONObject(request, MAX_BODY_BYTES);
      const questionRequest = validateQuestionRequest(body);

      const client = dependencies.createServiceClient();
      const configuration = await dependencies.loadRoute(client);
      if (!configuration) {
        throw new AppError(
          "server_misconfigured",
          "The recipe question service is not configured",
          503,
        );
      }
      const providerFactory = createRecipeQuestionProvider({
        enabled: true,
        route: configuration.route,
        model: configuration.model,
        provider: configuration.provider,
        resolveSecret: (reference) => dependencies.resolveSecret(client, reference),
        transport: dependencies.transport,
      });
      const provider: QuestionProviderPort = {
        answer: (input, signal) => providerFactory(input, signal),
      };
      const handler = createQuestionHandler({
        provider,
        metering: dependencies.metering,
      });
      const response = await handler(questionRequest, user.id);
      return json(response, 200, headers);
    } catch (error) {
      return errorResponse(error, headers);
    }
  };
}

// Supabase Edge Runtime entrypoint.
Deno.serve(createRecipeQuestionsHandler());
