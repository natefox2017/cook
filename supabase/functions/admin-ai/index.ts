// Developer: gengyun
// Purpose: Start the admin AI provider and usage endpoint.

import "jsr:@supabase/functions-js@2.117.3/edge-runtime.d.ts";
import { handleRequest } from "./handler.ts";

Deno.serve((req) => handleRequest(req));
