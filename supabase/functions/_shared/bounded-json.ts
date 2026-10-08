// Developer: RecipePouch
// Purpose: Parse small Edge JSON requests without unbounded buffering.

import { AppError } from "./errors.ts";

export async function readBoundedJSONObject(
  request: Request,
  maxBytes: number,
): Promise<Record<string, unknown>> {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > 65_536) {
    throw new Error("Invalid request body size limit.");
  }

  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    throw new AppError("validation_error", "Request body is too large", 413);
  }
  if (!request.body) {
    throw new AppError("validation_error", "Invalid JSON body", 400);
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      bytes += next.value.byteLength;
      // Enforce the same bound for chunked/missing/dishonest Content-Length.
      if (bytes > maxBytes) {
        await reader.cancel().catch(() => undefined);
        throw new AppError("validation_error", "Request body is too large", 413);
      }
      chunks.push(next.value);
    }

    const body = new Uint8Array(bytes);
    let offset = 0;
    for (const chunk of chunks) {
      body.set(chunk, offset);
      offset += chunk.byteLength;
    }

    const decoded = new TextDecoder("utf-8", { fatal: true }).decode(body);
    const value: unknown = JSON.parse(decoded);
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new AppError("validation_error", "Expected a JSON object", 400);
    }
    return value as Record<string, unknown>;
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw new AppError("validation_error", "Invalid JSON body", 400);
  } finally {
    reader.releaseLock();
  }
}
