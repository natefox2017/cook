// Developer: gengyun
// Purpose: Enforce the frozen import request field and one-of input contract.

const ALLOWED_KEYS = new Set([
  "client_request_id",
  "input_type",
  "url",
  "text",
  "artifact_id",
  "platform_hint",
  "original_source_url",
]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function hasImportRequestShape(
  request: Record<string, unknown>,
): boolean {
  if (Object.keys(request).some((key) => !ALLOWED_KEYS.has(key))) {
    return false;
  }

  const hasURL = Object.hasOwn(request, "url");
  const hasText = Object.hasOwn(request, "text");
  const hasArtifact = Object.hasOwn(request, "artifact_id");

  switch (request.input_type) {
    case "url":
      return typeof request.url === "string" && !hasText && !hasArtifact;
    case "text":
      return typeof request.text === "string" && !hasURL && !hasArtifact;
    case "image":
    case "file":
      return typeof request.artifact_id === "string" &&
        UUID.test(request.artifact_id) && !hasURL && !hasText;
    default:
      return false;
  }
}
