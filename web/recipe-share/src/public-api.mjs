// Developer: gengyun
// Purpose: Bound untrusted public recipe API responses before parsing JSON.

export async function readPublicRecipeJSON(response, maxBytes = 2 * 1024 * 1024) {
  const contentType = response.headers.get('content-type')?.split(';', 1)[0].trim().toLowerCase();
  if (contentType !== 'application/json' && !/^application\/[a-z0-9.+_-]+\+json$/.test(contentType ?? '')) {
    await response.body?.cancel().catch(() => {});
    throw new Error('Unsupported public recipe response type');
  }
  const length = response.headers.get('content-length');
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > maxBytes)) {
    await response.body?.cancel().catch(() => {});
    throw new Error('Public recipe response exceeds size limit');
  }
  if (!response.body || !Number.isSafeInteger(maxBytes) || maxBytes < 1) {
    throw new Error('Invalid public recipe response');
  }
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) throw new Error('Public recipe response exceeds size limit');
      chunks.push(value);
    }
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
}
