// Developer: gengyun
// Purpose: Serve the repository-scoped OpenAPI contract without runtime fetches.

import { handleRequest } from "./handler.ts";

Deno.serve(handleRequest);
