// Developer: gengyun
// Purpose: Bind the existing verified Auth and versioned AES-GCM libraries explicitly.
import { requireUser } from "../_shared/auth.ts";
import { resolveAISecret } from "../_shared/ai-secret.ts";
import {
  type BackendAdapterOptions,
  createRecipeDraftBackendAdapter,
} from "./backendAdapter.ts";

export function createRecipeDraftBackendBindings(
  options: Omit<BackendAdapterOptions, "authenticate" | "decryptAISecret">,
) {
  return createRecipeDraftBackendAdapter({
    ...options,
    authenticate: requireUser,
    decryptAISecret: resolveAISecret,
  });
}
