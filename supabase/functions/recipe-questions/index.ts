// Developer: gengyun
// Purpose: Authenticated, bounded recipe Q&A Edge Function entrypoint. It loads the canonical owned
// recipe snapshot from user_snapshots (never trusts the client snapshot for authorization), wires the
// durable phase-II metering and answer store, and refuses to re-dispatch a provider on a retry.

import "jsr:@supabase/functions-js@2.117.3/edge-runtime.d.ts";

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.117.3";
import { readBoundedJSONObject } from "../_shared/bounded-json.ts";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import { requireUser, createServiceClient } from "../_shared/auth.ts";
import { resolveAISecret, type AISecret } from "../_shared/ai-secret.ts";
import { createAIDraftSafeTransport } from "../recipe-import-worker/aiDraftSafeTransport.ts";
import type { InternalUsageRPC } from "../_shared/recipeInternalUsage.ts";
import {
  createQuestionHandler,
  validateQuestionRequest,
  type QuestionAnswerStore,
  type QuestionMeteringPort,
  type QuestionProviderPort,
  type QuestionSnapshot,
} from "./handler.ts";
import { createLedgerQuestionMetering } from "./questionMetering.ts";
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
  metering: (client: ServiceClient) => QuestionMeteringPort;
  answers: (client: ServiceClient) => QuestionAnswerStore;
  loadCanonicalRecipe: (
    client: ServiceClient,
    ownerId: string,
    recipeId: string,
  ) => Promise<QuestionSnapshot>;
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

/**
 * Load the canonical owned recipe snapshot from user_snapshots. The client snapshot is never trusted
 * for authorization: a recipe id absent from the owner's snapshot (or a missing snapshot) is not found.
 */
async function loadCanonicalRecipe(
  client: ServiceClient,
  ownerId: string,
  recipeId: string,
): Promise<QuestionSnapshot> {
  const { data: snapshot, error } = await client
    .from("user_snapshots")
    .select("payload")
    .eq("user_id", ownerId)
    .single();
  if (error || !snapshot) {
    throw new AppError("not_found", "Recipe snapshot was not found.", 404);
  }
  const payload = snapshot.payload as Record<string, unknown> | null;
  const recipes = payload?.recipes;
  if (!Array.isArray(recipes)) {
    throw new AppError("not_found", "Recipe was not found.", 404);
  }
  const recipe = recipes.find(
    (entry) =>
      typeof entry === "object" && entry !== null &&
      (entry as Record<string, unknown>).id === recipeId,
  ) as Record<string, unknown> | undefined;
  if (!recipe) {
    throw new AppError("not_found", "Recipe was not found.", 404);
  }
  const title = typeof recipe.title === "string" ? recipe.title.trim() : "";
  if (!title) {
    throw new AppError("not_found", "Recipe was not found.", 404);
  }
  const ingredients = (Array.isArray(recipe.ingredients) ? recipe.ingredients : [])
    .filter((entry) => typeof entry === "object" && entry !== null)
    .map((entry) => {
      const row = entry as Record<string, unknown>;
      const name = typeof row.name === "string" ? row.name.trim() : "";
      const amount = typeof row.amountText === "string" ? row.amountText.trim() : "";
      return amount ? `${name} ${amount}`.trim() : name;
    })
    .filter((text) => text.length > 0);
  const steps = (Array.isArray(recipe.steps) ? recipe.steps : [])
    .filter((entry) => typeof entry === "object" && entry !== null)
    .map((entry) => {
      const instruction = (entry as Record<string, unknown>).instruction;
      return typeof instruction === "string" ? instruction.trim() : "";
    })
    .filter((text) => text.length > 0);
  const source = typeof recipe.sourceURL === "string"
    ? recipe.sourceURL
    : typeof recipe.sourceName === "string"
    ? recipe.sourceName
    : null;
  return { title, ingredients, steps, source };
}

const ledgerRPC = (client: ServiceClient): InternalUsageRPC => {
  return async (name, args) => {
    const { data, error } = await client.rpc(name, args);
    if (error) {
      throw new AppError("internal_error", "The metering service is unavailable.", 503);
    }
    return (data as Record<string, unknown>) ?? {};
  };
};

const answersStore = (client: ServiceClient): QuestionAnswerStore => ({
  async load(ownerId, operationId) {
    const { data, error } = await client
      .from("recipe_question_answers")
      .select("id,input_hash,answer")
      .eq("owner_id", ownerId)
      .eq("operation_id", operationId)
      .maybeSingle();
    if (error) {
      throw new AppError("internal_error", "The answer store is unavailable.", 503);
    }
    if (!data) return null;
    return {
      id: data.id as string,
      input_hash: data.input_hash as string,
      answer: data.answer as { answer: string; statements: [] },
    };
  },
  async persist(ownerId, recipeId, operationId, inputHash, question, answer, payloadHash) {
    const { data, error } = await client
      .from("recipe_question_answers")
      .insert({
        owner_id: ownerId,
        recipe_id: recipeId,
        operation_id: operationId,
        input_hash: inputHash,
        question,
        answer,
        payload_hash: payloadHash,
      })
      .select("id")
      .single();
    if (error || !data) {
      throw new AppError("internal_error", "The answer store is unavailable.", 503);
    }
    return data.id as string;
  },
});

const productionDependencies: RecipeQuestionsDependencies = {
  authenticate: requireUser,
  createServiceClient,
  loadRoute: loadQuestionRoute,
  resolveSecret: resolveQuestionSecret,
  transport: createAIDraftSafeTransport(),
  metering: (client) => createLedgerQuestionMetering(ledgerRPC(client)),
  answers: (client) => answersStore(client),
  loadCanonicalRecipe,
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
      // Authorize the recipe against the owner's canonical snapshot, then replace the client snapshot.
      questionRequest.snapshot = await dependencies.loadCanonicalRecipe(
        client,
        user.id,
        questionRequest.recipe_id,
      );

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
        metering: dependencies.metering(client),
        answers: dependencies.answers(client),
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
