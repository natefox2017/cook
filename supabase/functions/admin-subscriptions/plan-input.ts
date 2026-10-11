import { AppError } from "../_shared/errors.ts";

function text(
  body: Record<string, unknown>,
  key: string,
  limit: number,
): string {
  const value = body[key];
  if (typeof value !== "string" || !value.trim() || value.length > limit) {
    throw new AppError(
      "validation_error",
      `${key} must be a nonempty string of at most ${limit} characters`,
      400,
    );
  }
  return value.trim();
}

export function parsePlanBody(body: Record<string, unknown>) {
  const planKey = text(body, "planKey", 120);
  const displayName = text(body, "displayName", 200);
  const productId = text(body, "productId", 256);
  const currency = text(body, "currency", 3).toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) {
    throw new AppError(
      "validation_error",
      "currency must be a three-letter code",
      400,
    );
  }
  const platform = body.platform;
  if (platform !== "app_store" && platform !== "play_store") {
    throw new AppError(
      "validation_error",
      "platform must be app_store or play_store",
      400,
    );
  }
  const billingPeriod = body.billingPeriod;
  if (
    billingPeriod !== "monthly" && billingPeriod !== "yearly" &&
    billingPeriod !== "lifetime"
  ) {
    throw new AppError("validation_error", "invalid billingPeriod", 400);
  }
  const price = body.price;
  if (typeof price !== "number" || !Number.isFinite(price) || price < 0) {
    throw new AppError(
      "validation_error",
      "price must be a non-negative number",
      400,
    );
  }
  if (typeof body.active !== "boolean") {
    throw new AppError("validation_error", "active must be a boolean", 400);
  }
  const description = body.description;
  if (
    description != null &&
    (typeof description !== "string" || description.length > 4000)
  ) {
    throw new AppError(
      "validation_error",
      "description must be a string of at most 4000 characters or null",
      400,
    );
  }
  return {
    plan_key: planKey,
    display_name: displayName,
    platform,
    product_id: productId,
    price,
    currency,
    billing_period: billingPeriod,
    active: body.active,
    description: typeof description === "string"
      ? description.trim() || null
      : null,
  };
}
