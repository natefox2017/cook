// Developer: gengyun
// Purpose: Read bounded UTF-8 request objects while rejecting duplicate JSON keys.
export class RequestJSONError extends Error {
  code: "INPUT_TOO_LARGE" | "INVALID_INPUT";
  constructor(code: "INPUT_TOO_LARGE" | "INVALID_INPUT") {
    super(code);
    this.code = code;
  }
}
export const BODY_LIMIT = 32768;
export async function readRequestJSON(
  request: Request,
): Promise<Record<string, unknown>> {
  const invalid = () => {
    throw new RequestJSONError("INVALID_INPUT");
  };
  const length = request.headers.get("content-length");
  if (length && /^\d+$/.test(length) && BigInt(length) > BigInt(BODY_LIMIT)) {
    throw new RequestJSONError("INPUT_TOO_LARGE");
  }
  if (!request.body) return invalid();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.byteLength;
      if (size > BODY_LIMIT) {
        void reader.cancel().catch(() => {});
        throw new RequestJSONError("INPUT_TOO_LARGE");
      }
      chunks.push(chunk.value);
    }
  } finally {
    try {
      reader.releaseLock();
    } catch { /* Cleanup must not replace the bounded-body error. */ }
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    // JSON.parse remains the syntax authority; this bounded scanner detects keys lost by it.
    const parsed: unknown = JSON.parse(text);
    let pos = 0;
    const space = () => {
      while (/[\t\r\n ]/.test(text[pos] ?? "x")) pos++;
    };
    function string(): string {
      const start = pos++;
      while (pos < text.length) {
        if (text[pos] === "\\") {
          pos += 2;
          continue;
        }
        if (text[pos++] === '"') return JSON.parse(text.slice(start, pos));
      }
      return invalid();
    }
    function scan(depth: number): void {
      if (depth > 32) invalid();
      space();
      const char = text[pos];
      if (char === '"') {
        string();
        return;
      }
      if (char === "{" || char === "[") {
        const object = char === "{";
        const close = object ? "}" : "]";
        const keys = new Set<string>();
        pos++;
        space();
        if (text[pos] === close) {
          pos++;
          return;
        }
        while (true) {
          space();
          if (object) {
            const key = string();
            if (keys.has(key)) invalid();
            keys.add(key);
            space();
            pos++;
          }
          scan(depth + 1);
          space();
          if (text[pos++] === close) break;
        }
      } else while (pos < text.length && !/[\s,}\]]/.test(text[pos])) pos++;
    }
    scan(0);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      invalid();
    }
    return parsed as Record<string, unknown>;
  } catch (error) {
    if (error instanceof RequestJSONError) throw error;
    return invalid();
  }
}
