# Supabase Architecture V1

Backend uses Supabase.

Components:

- Auth
- PostgreSQL
- Storage
- Edge Functions
- Queues
- Realtime

Core tables:

- users
- recipes
- recipe_sources
- recipe_ingredients
- recipe_steps
- import_jobs
- import_evidence
- artifacts
- grocery_items
- meal_plans

Security:

- RLS required
- Service keys only server side
- User ownership on all private data

Processing:

iOS
→ Edge Function
→ Queue
→ AI Worker
→ Database
→ Realtime update
