import type { createServiceClient } from "../_shared/auth.ts";
import { AppError } from "../_shared/errors.ts";

type Client = ReturnType<typeof createServiceClient>;
export type FactorSnapshot = {
  totp_secret_ciphertext: string | null;
  totp_enabled_at: string | null;
  totp_last_counter: number;
};

export async function savePendingFactor(
  client: Client,
  adminId: string,
  ciphertext: string,
  current: FactorSnapshot | null,
) {
  if (current?.totp_enabled_at) throw changed();
  const payload = {
    admin_id: adminId,
    totp_secret_ciphertext: ciphertext,
    totp_enabled_at: null,
    totp_last_counter: -1,
    updated_at: new Date().toISOString(),
  };
  let query;
  if (current) {
    query = client.from("admin_auth_factors").update(payload).eq(
      "admin_id",
      adminId,
    ).is("totp_enabled_at", null);
    query = current.totp_secret_ciphertext === null
      ? query.is("totp_secret_ciphertext", null)
      : query.eq("totp_secret_ciphertext", current.totp_secret_ciphertext);
  } else {
    query = client.from("admin_auth_factors").insert(payload);
  }
  const { data, error } = await query.select("admin_id").maybeSingle();
  if (error?.code === "23505") throw changed();
  if (error) {
    throw new AppError("internal_error", "Unable to prepare TOTP setup", 500);
  }
  if (!data) throw changed();
}

export async function removeObservedFactor(
  client: Client,
  adminId: string,
  current: FactorSnapshot | null,
) {
  if (!current) return;
  let query = client.from("admin_auth_factors").delete().eq("admin_id", adminId)
    .eq("totp_last_counter", current.totp_last_counter);
  query = current.totp_secret_ciphertext === null
    ? query.is("totp_secret_ciphertext", null)
    : query.eq("totp_secret_ciphertext", current.totp_secret_ciphertext);
  query = current.totp_enabled_at === null
    ? query.is("totp_enabled_at", null)
    : query.eq("totp_enabled_at", current.totp_enabled_at);
  const { data, error } = await query.select("admin_id").maybeSingle();
  if (error) throw new AppError("internal_error", "Unable to remove TOTP", 500);
  if (!data) throw changed();
}

function changed() {
  return new AppError(
    "conflict",
    "TOTP settings changed. Refresh and try again.",
    409,
  );
}
