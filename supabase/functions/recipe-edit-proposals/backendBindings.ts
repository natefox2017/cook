// Developer: gengyun
// Purpose: Bind the verified JWT owner, the owner-scoped persistence adapter, and the injected
// provider/usage ports into the handler dependencies. Real provider config and the usage ledger are
// wired by the composition root; when absent they fail closed instead of faking success.

import { requireUser } from "../_shared/auth.ts";
import { type Dependencies, type EditProviderPort, Failure } from "./handler.ts";
import {
  type BackendAdapterOptions,
  createRecipeEditBackendAdapter,
} from "./backendAdapter.ts";
import { createUnavailableUsagePort, type UsagePort } from "./usagePort.ts";

export interface RecipeEditBindingsOptions
  extends Partial<BackendAdapterOptions> {
  enabled?: boolean;
  provider?: EditProviderPort;
  usage?: UsagePort;
}

export function createRecipeEditBindings(
  options: RecipeEditBindingsOptions,
): Dependencies {
  const backend = createRecipeEditBackendAdapter(options);
  return {
    enabled: options.enabled === true,
    authenticate: async (request: Request) => {
      try {
        const { user } = await requireUser(request);
        if (user.is_anonymous) throw new Failure("UNAUTHORIZED");
        return { id: user.id };
      } catch (error) {
        // requireUser throws AppError(401) for missing/invalid/expired sessions; map to the
        // handler's Failure vocabulary so it surfaces as 401 instead of 500.
        if (error instanceof Failure) throw error;
        throw new Failure("UNAUTHORIZED");
      }
    },
    backend,
    // When no provider is injected, generation is refused (503) instead of faking a result.
    provider: options.provider ?? {
      generate: async () => {
        throw new Failure("PROVIDER_UNAVAILABLE");
      },
    },
    usage: options.usage ?? createUnavailableUsagePort(),
  };
}
