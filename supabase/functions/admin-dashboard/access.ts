// Developer: RecipePouch
// Purpose: Restrict dashboard data to the documented owner role.

import { requireAdminRole } from "../_shared/admin-role.ts";

export function requireDashboardRole(role: unknown): void {
  requireAdminRole(role, ["owner"]);
}
