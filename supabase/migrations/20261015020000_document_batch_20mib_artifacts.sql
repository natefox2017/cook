-- Developer: gengyun
-- Purpose: Raise the private import artifact ceiling to the DEV-443 20 MiB batch contract.
-- Additive only: widens the per-file bound for document batches without touching
-- retention, ownership, or the single-source 10 MiB worker path.

alter table public.recipe_import_artifacts
    drop constraint if exists recipe_import_artifacts_size_bytes_check;

alter table public.recipe_import_artifacts
    add constraint recipe_import_artifacts_size_bytes_check
        check (size_bytes between 1 and 20971520);

update storage.buckets
set file_size_limit = 20971520
where id = 'recipe-import-artifacts';
