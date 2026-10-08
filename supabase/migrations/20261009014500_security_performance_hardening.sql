-- Developer: RecipePouch
-- Purpose: Apply Supabase advisor fixes without changing owner-scoped access rules.
-- Apply after the existing migrations; do not rewrite production migration history.

-- Trigger/helper functions use explicit public references or pg_catalog builtins.
-- Pin the search path so roles cannot change name resolution at execution time.
alter function public.touch_subscription_plans_updated_at() set search_path = '';
alter function public.touch_runtime_config_updated_at() set search_path = '';
alter function public.touch_payment_transactions_updated_at() set search_path = '';
alter function public.map_commerce_store(text) set search_path = '';
alter function public.map_commerce_platform(text) set search_path = '';

-- Cover foreign-key lookups and cascades reported by the database advisor.
create index if not exists ai_routes_primary_model_id_idx on public.ai_routes (primary_model_id);
create index if not exists ai_usage_events_final_model_id_idx on public.ai_usage_events (final_model_id);
create index if not exists ai_usage_events_model_id_idx on public.ai_usage_events (model_id);
create index if not exists payment_transactions_purchase_event_id_idx on public.payment_transactions (purchase_event_id);
create index if not exists store_integrations_secret_ref_idx on public.store_integrations (secret_ref);

-- Preserve each policy's owner check and additional domain restrictions.
-- Wrapping auth.uid() in SELECT enables a per-statement initPlan instead
-- of evaluating the same JWT-derived value once for every candidate row.
-- Existing policy roles, commands, grants and permissiveness are unchanged.

alter policy "profiles_select_own" on public.profiles using ((select auth.uid()) = id);
alter policy "profiles_insert_own" on public.profiles with check ((select auth.uid()) = id);
alter policy "profiles_update_own" on public.profiles using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

alter policy "subscriptions_select_own" on public.subscriptions using ((select auth.uid()) = user_id);

alter policy "purchase_events_select_own" on public.purchase_events using ((select auth.uid()) = user_id);

alter policy "recipes_select_own" on public.recipes using ((select auth.uid()) = user_id);
alter policy "recipes_insert_own" on public.recipes with check ((select auth.uid()) = user_id);
alter policy "recipes_update_own" on public.recipes using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
alter policy "recipes_delete_own" on public.recipes using ((select auth.uid()) = user_id);

alter policy "collections_select_own" on public.collections using ((select auth.uid()) = user_id);
alter policy "collections_insert_own" on public.collections with check ((select auth.uid()) = user_id);
alter policy "collections_update_own" on public.collections using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
alter policy "collections_delete_own" on public.collections using ((select auth.uid()) = user_id);

alter policy "grocery_lists_select_own" on public.grocery_lists using ((select auth.uid()) = user_id);
alter policy "grocery_lists_insert_own" on public.grocery_lists with check ((select auth.uid()) = user_id);
alter policy "grocery_lists_update_own" on public.grocery_lists using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
alter policy "grocery_lists_delete_own" on public.grocery_lists using ((select auth.uid()) = user_id);

alter policy "meal_plans_select_own" on public.meal_plans using ((select auth.uid()) = user_id);
alter policy "meal_plans_insert_own" on public.meal_plans with check (((select auth.uid()) = user_id) and public.user_owns_recipe(recipe_id));
alter policy "meal_plans_update_own" on public.meal_plans using ((select auth.uid()) = user_id) with check (((select auth.uid()) = user_id) and public.user_owns_recipe(recipe_id));
alter policy "meal_plans_delete_own" on public.meal_plans using ((select auth.uid()) = user_id);

alter policy "pantry_items_select_own" on public.pantry_items using ((select auth.uid()) = user_id);
alter policy "pantry_items_insert_own" on public.pantry_items with check ((select auth.uid()) = user_id);
alter policy "pantry_items_update_own" on public.pantry_items using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
alter policy "pantry_items_delete_own" on public.pantry_items using ((select auth.uid()) = user_id);

alter policy "payment_transactions_select_own" on public.payment_transactions using ((select auth.uid()) = user_id);

alter policy "ingredients_select_visible" on public.ingredients using (is_system = true or user_id = (select auth.uid()));
alter policy "ingredients_insert_own" on public.ingredients with check (user_id = (select auth.uid()) and is_system = false);
alter policy "ingredients_update_own" on public.ingredients using (user_id = (select auth.uid()) and is_system = false) with check (user_id = (select auth.uid()) and is_system = false);
alter policy "ingredients_delete_own" on public.ingredients using (user_id = (select auth.uid()) and is_system = false);
