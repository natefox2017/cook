// Developer: gengyun
// Purpose: Authenticated recipe-translation endpoint with bounded IO and a safe provider.

import {
  buildPrompt,
  DEADLINE_MS,
  MAX_INPUT_BYTES,
  MAX_OUTPUT_BYTES,
  parseRequest,
  TranslationContractError,
  validateProviderOutput,
} from "./contract.ts";
import { configuredTranslationProvider, type TranslationProvider } from "./provider.ts";
import { requireUser } from "../_shared/auth.ts";
import { readBoundedJSONObject } from "../_shared/bounded-json.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";

export interface TranslationDependencies {
  verifiedOwner(request: Request): Promise<{ id: string } | null>;
  provider: TranslationProvider | null;
}

const productionDependencies: TranslationDependencies = {
  async verifiedOwner(request: Request) {
    const { user } = await requireUser(request);
    return { id: user.id };
  },
  provider: configuredTranslationProvider(),
};

export async function handleRequest(
  req: Request,
  dependencies: TranslationDependencies = productionDependencies,
): Promise<Response> {
  const cors = authCorsHeaders(req);
  const preflight = handleCors(req, "auth");
  if (preflight) return preflight;
  if (req.method !== "POST") {
    return errorResponse(new AppError("method_not_allowed", "Method not allowed", 405), cors);
  }

  try {
    const owner = await dependencies.verifiedOwner(req);
    if (!owner) {
      return errorResponse(new AppError("unauthorized", "Invalid or expired session", 401), cors);
    }
    const body = await readBoundedJSONObject(req, MAX_INPUT_BYTES);
    const request = parseRequest(body);
    if (!dependencies.provider) {
      throw new AppError("server_misconfigured", "Translation provider is not configured.", 503);
    }
    const signal = AbortSignal.timeout(DEADLINE_MS);
    const raw = await dependencies.provider(buildPrompt(request), signal);
    const proposal = validateProviderOutput(raw, request);
    if (JSON.stringify(proposal).length > MAX_OUTPUT_BYTES) {
      throw new AppError("internal_error", "Translation proposal exceeded its limit.", 502);
    }
    return json(proposal, 200, cors);
  } catch (error) {
    if (error instanceof TranslationContractError) {
      if (error.code === "invalid_provider_output") {
        return errorResponse(new AppError("internal_error", error.message, 502), cors);
      }
      return errorResponse(new AppError("validation_error", error.message, 400), cors);
    }
    if (error instanceof DOMException && (error.name === "TimeoutError" || error.name === "AbortError")) {
      return errorResponse(new AppError("internal_error", "Translation timed out.", 503), cors);
    }
    return errorResponse(error, cors);
  }
}
