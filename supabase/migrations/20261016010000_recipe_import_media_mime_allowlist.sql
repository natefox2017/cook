-- Developer: gengyun
-- Purpose: Widen the owner-scoped import artifact MIME allowlist for the DEV-78
--          finite media containers (mp3/m4a/wav/mp4). Additive only: existing
--          image/pdf/text rows and the text/plain WebVTT upload path stay valid.
--          SOURCE ONLY — not applied; no live DB mutation is authorized yet.

alter table public.recipe_import_artifacts
    drop constraint if exists recipe_import_artifacts_mime_type_check;
alter table public.recipe_import_artifacts
    add constraint recipe_import_artifacts_mime_type_check
        check (mime_type in (
            'image/jpeg', 'image/png', 'image/heic', 'image/heif',
            'application/pdf', 'text/plain',
            'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/x-m4a',
            'audio/m4a', 'audio/wav', 'audio/x-wav', 'video/mp4'
        ));

alter table public.recipe_import_artifacts
    drop constraint if exists recipe_import_artifacts_check;
alter table public.recipe_import_artifacts
    add constraint recipe_import_artifacts_check
        check (
            (input_type = 'image' and kind = 'screenshot'
                and mime_type like 'image/%')
            or (input_type = 'file' and kind = 'original'
                and mime_type in (
                    'application/pdf', 'text/plain',
                    'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/x-m4a',
                    'audio/m4a', 'audio/wav', 'audio/x-wav', 'video/mp4'
                ))
        );

update storage.buckets
set allowed_mime_types = array[
    'image/jpeg', 'image/png', 'image/heic', 'image/heif',
    'application/pdf', 'text/plain',
    'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/x-m4a',
    'audio/m4a', 'audio/wav', 'audio/x-wav', 'video/mp4'
]
where id = 'recipe-import-artifacts';
