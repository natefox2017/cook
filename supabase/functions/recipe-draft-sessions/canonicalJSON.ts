// Developer: gengyun
// Purpose: Canonicalize the bounded draft JSON domain without invoking user code.
export function scalarString(
  value: unknown,
  min = 0,
  max = Infinity,
): value is string {
  if (
    typeof value !== "string" ||
    /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u
      .test(value)
  ) return false;
  const length = [...value].length;
  return length >= min && length <= max;
}
export function canonicalJSON(value: unknown): string {
  const ancestors = new Set<object>();
  function encode(item: unknown, depth: number): string {
    if (depth > 64) throw new TypeError("JSON depth");
    if (item === null || typeof item === "boolean") return JSON.stringify(item);
    if (typeof item === "string") {
      if (!scalarString(item)) throw new TypeError("Unicode scalar required");
      return JSON.stringify(item);
    }
    if (typeof item === "number") {
      if (
        !Number.isFinite(item) ||
        (Number.isInteger(item) && !Number.isSafeInteger(item))
      ) throw new TypeError("JSON number");
      return JSON.stringify(item);
    }
    if (typeof item !== "object" || ancestors.has(item)) {
      throw new TypeError("JSON data required");
    }
    const proto = Object.getPrototypeOf(item);
    if (
      Array.isArray(item)
        ? proto !== Array.prototype
        : proto !== Object.prototype && proto !== null
    ) throw new TypeError("Plain JSON object required");
    const descriptors = Object.getOwnPropertyDescriptors(item);
    if (Reflect.ownKeys(item).some((key) => typeof key !== "string")) {
      throw new TypeError("JSON keys");
    }
    for (const descriptor of Object.values(descriptors)) {
      if (descriptor.get || descriptor.set) {
        throw new TypeError("JSON accessor");
      }
    }
    ancestors.add(item);
    let result: string;
    if (Array.isArray(item)) {
      if (
        Object.keys(item).length !== item.length ||
        Object.keys(item).some((key, i) => key !== String(i))
      ) throw new TypeError("Dense JSON array required");
      const values: string[] = [];
      if (Reflect.ownKeys(item).length !== item.length + 1) {
        throw new TypeError("JSON array properties");
      }
      for (let i = 0; i < item.length; i++) {
        values.push(encode(descriptors[String(i)].value, depth + 1));
      }
      result = "[" + values.join(",") + "]";
    } else {
      result = "{" + Object.keys(item).sort().map((key) => {
        if (!scalarString(key)) throw new TypeError("Unicode key");
        return JSON.stringify(key) + ":" +
          encode(descriptors[key].value, depth + 1);
      }).join(",") + "}";
    }
    ancestors.delete(item);
    return result;
  }
  return encode(value, 0);
}
export async function canonicalHash(value: unknown): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonicalJSON(value)),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}
