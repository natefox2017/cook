import { requireAdminRole } from "../_shared/admin-role.ts";

const OWNER_ADMIN = ["owner", "admin"] as const;

/** Restrict catalog writes and subscription or revenue data to billing admins. */
export function authorizeSubscriptionRoute(
  role: unknown,
  resource: string,
  method: string,
): void {
  const planWrite = resource === "plans" &&
    ["POST", "PUT", "DELETE"].includes(method);
  const financialRead = ["records", "revenue"].includes(resource) &&
    method === "GET";

  if (planWrite || financialRead) {
    requireAdminRole(role, OWNER_ADMIN);
  }
}
