import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  type FactorSnapshot,
  removeObservedFactor,
  savePendingFactor,
} from "./factor-store.ts";
import { AppError } from "../_shared/errors.ts";

const initial: FactorSnapshot = {
  totp_secret_ciphertext: "old-cipher",
  totp_enabled_at: null,
  totp_last_counter: -1,
};
function fixture(row: FactorSnapshot | null) {
  let state = row ? { ...row } : null;
  const client = {
    from() {
      let operation = "";
      let payload: FactorSnapshot;
      const filters: Array<[string, unknown]> = [];
      const query = {
        update(value: FactorSnapshot) {
          operation = "update";
          payload = value;
          return query;
        },
        insert(value: FactorSnapshot) {
          operation = "insert";
          payload = value;
          return query;
        },
        delete() {
          operation = "delete";
          return query;
        },
        eq(key: string, value: unknown) {
          if (key !== "admin_id") filters.push([key, value]);
          return query;
        },
        is(key: string, value: unknown) {
          filters.push([key, value]);
          return query;
        },
        select() {
          return query;
        },
        async maybeSingle() {
          if (operation === "insert" && state) {
            return {
              data: null,
              error: { code: "23505" },
            };
          }
          const matches = operation === "insert" ||
            (state &&
              filters.every(([k, v]) =>
                (state as unknown as Record<string, unknown>)[k] === v
              ));
          if (!matches) return { data: null, error: null };
          state = operation === "delete" ? null : { ...payload };
          return { data: { admin_id: "fixture" }, error: null };
        },
      };
      return query;
    },
  };
  return {
    client: client as never,
    state: () => state,
    replace: (value: FactorSnapshot) => {
      state = { ...value };
    },
  };
}
Deno.test("pending setup never disables a concurrently enabled factor or replaces a newer setup", async () => {
  for (
    const changed of [{ ...initial, totp_enabled_at: "2026-01-01T00:00:00Z" }, {
      ...initial,
      totp_secret_ciphertext: "newer-cipher",
    }]
  ) {
    const f = fixture(changed);
    await assertRejects(
      () => savePendingFactor(f.client, "fixture", "replacement", initial),
      AppError,
    );
    assertEquals(f.state(), changed);
  }
  const f = fixture(initial);
  await assertRejects(
    () => savePendingFactor(f.client, "fixture", "replacement", null),
    AppError,
  );
  assertEquals(f.state(), initial);
});
Deno.test("setup allows a fresh insert or the exact disabled snapshot", async () => {
  for (const row of [null, initial]) {
    const f = fixture(row);
    await savePendingFactor(f.client, "fixture", "replacement", row);
    assertEquals(f.state()?.totp_secret_ciphertext, "replacement");
  }
});
Deno.test("removal binds ciphertext, enabled state and counter and rejects replay", async () => {
  const enabled = {
    ...initial,
    totp_enabled_at: "2026-01-01T00:00:00Z",
    totp_last_counter: 4,
  };
  for (
    const changed of [{ ...enabled, totp_secret_ciphertext: "newer-cipher" }, {
      ...enabled,
      totp_last_counter: 5,
    }, { ...enabled, totp_enabled_at: "2026-02-01T00:00:00Z" }]
  ) {
    const f = fixture(changed);
    await assertRejects(
      () => removeObservedFactor(f.client, "fixture", enabled),
      AppError,
    );
    assertEquals(f.state(), changed);
  }
  const f = fixture(enabled);
  await removeObservedFactor(f.client, "fixture", enabled);
  assertEquals(f.state(), null);
  await assertRejects(
    () => removeObservedFactor(f.client, "fixture", enabled),
    AppError,
  );
  await removeObservedFactor(f.client, "fixture", null);
});
