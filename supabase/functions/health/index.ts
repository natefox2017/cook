// Developer: RecipePouch
// Purpose: Authenticated backend capability status without mutable remote imports.

import "jsr:@supabase/functions-js@2.117.3/edge-runtime.d.ts";
import { createHealthHandler } from "./handler.ts";

// Supabase Edge Runtime entrypoint.
Deno.serve(createHealthHandler());
