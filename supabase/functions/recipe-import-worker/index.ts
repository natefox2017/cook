// Developer: gengyun
// Purpose: Processes owner-scoped imports and extracts evidenced public recipe page content.

import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  attachPageTextEvidence,
  incompleteArtifactRecipe,
  incompleteWebRecipe,
  parseSchemaOrgRecipePage,
} from "./schemaRecipe.ts";
import {
  fetchPublicHTML,
  SafeFetchError,
  type SafeHTMLPage,
} from "./safeURLFetch.ts";
import { extractPublicPageText } from "./pageContent.ts";
import { parseLocalText } from "./textEvidence.ts";
import {
  OCRArtifactError,
  parsePrivateOCRArtifact,
} from "./artifactOCR.ts";
import { configuredOCRProvider } from "./approvedOCRProvider.ts";
import {
  ArtifactTextError,
  decodePlainTextArtifact,
  isOwnerScopedAvailableArtifact,
  parsePlainTextArtifact,
  type PrivateArtifactRow,
} from "./artifactText.ts";

interface QueueMessage {
  msg_id: number;
  read_ct: number;
  message: { job_id?: string; owner_id?: string; contract_version?: number };
}

interface Job {
  id: string;
  owner_id: string;
  input_type: "url" | "text" | "image" | "file";
  source_value: string;
  artifact_id: string | null;
  original_source_url: string | null;
  platform_hint: string | null;
  status: string;
  attempt_count: number;
  queue_message_id: number | null;
  updated_at: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const now = () => new Date().toISOString();

function secureEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let difference = a.length ^ b.length;
  for (let index = 0; index < Math.max(a.length, b.length); index++) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    return Response.json({ error: "POST required" }, { status: 405 });
  }

  // This endpoint intentionally has verify_jwt=false for scheduled service
  // invocations; the extra secret is mandatory and never committed to Git.
  const requiredSecret = Deno.env.get("RECIPE_IMPORT_WORKER_SECRET");
  if (
    !requiredSecret || !secureEqual(
      requiredSecret,
      request.headers.get("x-recipe-worker-secret") ?? "",
    )
  ) {
    return Response.json({ error: "Not authorized" }, { status: 401 });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRole) {
    return Response.json({ error: "Worker configuration missing" }, {
      status: 503,
    });
  }

  const admin = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: messages, error: readError } = await admin.rpc(
    "recipe_import_v1_queue_read",
    { p_vt: 120, p_qty: 5 },
  );
  if (readError) {
    console.error("recipe_worker_queue_read_failed", readError.code);
    return Response.json({ error: "Queue unavailable" }, { status: 503 });
  }

  let completed = 0;
  let failed = 0;
  let deferred = 0;

  for (const item of (messages ?? []) as QueueMessage[]) {
    const jobID = item.message?.job_id;
    const queueID = item.msg_id;
    if (!jobID || !UUID.test(jobID) || item.message.contract_version !== 1) {
      console.error("recipe_worker_unsupported_message", { msg_id: queueID });
      // Do not delete unknown/legacy queue messages. Their producers may use
      // a different schema, and purging them here would destroy source data.
      deferred++;
      continue;
    }

    try {
      const { data: existing, error: getError } = await admin.from(
        "recipe_import_jobs",
      ).select("*").eq("id", jobID).maybeSingle();
      if (getError) throw getError;

      // An account deleted during processing may leave a transient message.
      // The job row is owner-cascaded, so no recipe may be recreated.
      if (!existing) {
        await archive(queueID);
        continue;
      }
      const job = existing as Job;
      if (job.owner_id !== item.message.owner_id) {
        console.error("recipe_worker_wrong_owner_message", { msg_id: queueID });
        deferred++;
        continue;
      }

      if (job.queue_message_id !== queueID) {
        // A retried job can have a newer committed queue message. The old
        // message is superseded and must not occupy the queue forever; archive
        // it only after verifying the persisted job points to a different ID.
        await archive(queueID);
        continue;
      }

      if (job.status === "completed" || job.status === "failed") {
        await archive(queueID);
        continue;
      }

      const { data: claims, error: claimError } = await admin.rpc(
        "claim_recipe_import_job",
        { p_job_id: jobID, p_message_id: queueID },
      );
      if (claimError) throw claimError;
      const claimed = (Array.isArray(claims) ? claims[0] : claims) as
        | Job
        | undefined;
      if (!claimed) {
        // In-flight jobs have a visibility timeout and are reclaimed if their
        // lease becomes stale; never ACK a message while work may be ongoing.
        deferred++;
        continue;
      }

      if (claimed.status === "failed") {
        await archive(queueID);
        failed++;
        continue;
      }

      // A second worker may reclaim an expired lease before this invocation
      // finishes. All writes must fence on the claimed attempt number so an
      // older worker cannot overwrite the newer attempt's result.
      const claimedAttempt = claimed.attempt_count;

      let result:
        | ReturnType<typeof parseLocalText>
        | ReturnType<
          typeof parseSchemaOrgRecipePage
        > = incompleteWebRecipe({
          id: claimed.id,
          originalURL: claimed.original_source_url ?? claimed.source_value,
          platformHint: claimed.platform_hint,
        });
      let completionError: Record<string, unknown> | null = null;
      if (claimed.input_type === "url") {
        let page: SafeHTMLPage | null = null;
        try {
          page = await fetchPublicHTML(claimed.source_value);
        } catch (error) {
          const sourceError = error instanceof SafeFetchError
            ? error
            : new SafeFetchError(
              "FETCH_BLOCKED",
              "The source webpage could not be fetched safely.",
              true,
            );
          result = incompleteWebRecipe({
            id: claimed.id,
            originalURL: claimed.original_source_url ?? claimed.source_value,
            platformHint: claimed.platform_hint,
          });
          completionError = {
            code: sourceError.code,
            message: sourceError.message,
            recoverable: sourceError.recoverable,
            suggested_action:
              "Keep this source and try a public recipe page or paste the recipe text.",
            request_id: crypto.randomUUID(),
          };
        }
        if (page) {
          const parsed = parseSchemaOrgRecipePage({
            id: claimed.id,
            html: page.html,
            source: {
              originalURL: claimed.original_source_url ?? claimed.source_value,
              canonicalURL: page.canonicalURL,
              platformHint: claimed.platform_hint,
            },
          });
          const pageEvidence = await extractPublicPageText(
            page.html,
            page.canonicalURL,
          );
          result = attachPageTextEvidence(parsed, pageEvidence);
        }
      } else if (claimed.input_type === "text") {
        result = parseLocalText({
          id: claimed.id,
          source_value: claimed.source_value,
          original_source_url: claimed.original_source_url,
          platform_hint: claimed.platform_hint,
        });
      } else {
        const { data: artifact, error: artifactError } = await admin.from(
          "recipe_import_artifacts",
        ).select("id,owner_id,input_type,mime_type,state,expires_at,storage_bucket,storage_path,size_bytes")
          .eq("id", claimed.artifact_id ?? "")
          .eq("owner_id", claimed.owner_id)
          .maybeSingle();
        if (artifactError) throw artifactError;
        const available = isOwnerScopedAvailableArtifact(
          artifact as PrivateArtifactRow | null,
          {
            ownerID: claimed.owner_id,
            artifactID: claimed.artifact_id,
            inputType: claimed.input_type,
          },
        );
        result = incompleteArtifactRecipe({
          id: claimed.id,
          inputType: claimed.input_type,
          artifactID: claimed.artifact_id ?? "",
          platformHint: claimed.platform_hint,
          mimeType: available ? artifact!.mime_type : null,
        });

        if (!available) {
          completionError = {
            code: "ARTIFACT_NOT_READY",
            message: "The private source attachment is no longer available.",
            recoverable: false,
            suggested_action: "Share the source again or add the recipe details manually.",
            request_id: crypto.randomUUID(),
          };
        } else if (claimed.input_type === "file" &&
          artifact!.mime_type === "text/plain") {
          // Download only after verifying the persisted owner, UUID path,
          // expiry, MIME and maximum size. Transient Storage errors throw so
          // the queue lease can be retried without losing the original job.
          const { data: file, error: downloadError } = await admin.storage
            .from(artifact!.storage_bucket)
            .download(artifact!.storage_path);
          if (downloadError || !file) {
            throw downloadError ?? new Error("Private artifact download failed");
          }
          try {
            const text = await decodePlainTextArtifact(
              file,
              artifact!.size_bytes,
            );
            result = parsePlainTextArtifact({
              id: claimed.id,
              text,
              artifactID: artifact!.id,
              platformHint: claimed.platform_hint,
              originalSourceURL: claimed.original_source_url,
            });
          } catch (error) {
            if (!(error instanceof ArtifactTextError)) throw error;
            completionError = {
              code: error.code,
              message: error.message,
              recoverable: false,
              suggested_action: "Edit the saved source as text or share a valid UTF-8 text file.",
              request_id: crypto.randomUUID(),
            };
          }
        } else if (
          claimed.input_type === "image" ||
          (claimed.input_type === "file" &&
            artifact!.mime_type === "application/pdf")
        ) {
          // Private bytes never leave Supabase unless the owner explicitly
          // enables an approved, server-configured OCR destination.
          const provider = configuredOCRProvider();
          if (provider) {
            const { data: file, error: downloadError } = await admin.storage
              .from(artifact!.storage_bucket)
              .download(artifact!.storage_path);
            if (downloadError || !file) {
              throw downloadError ??
                new Error("Private OCR source download failed");
            }
            try {
              const bytes = new Uint8Array(await file.arrayBuffer());
              if (bytes.length !== artifact!.size_bytes) {
                throw new OCRArtifactError(
                  "OCR_INVALID_SOURCE",
                  "The private source size changed after upload.",
                );
              }
              result = await parsePrivateOCRArtifact({
                recipeID: claimed.id,
                artifactID: artifact!.id,
                inputType: claimed.input_type,
                mimeType: artifact!.mime_type,
                bytes,
                platformHint: claimed.platform_hint,
                originalSourceURL: claimed.original_source_url,
                provider,
              });
            } catch (error) {
              if (!(error instanceof OCRArtifactError)) throw error;
              completionError = {
                code: error.code,
                message: error.message,
                recoverable: error.code === "OCR_UNAVAILABLE",
                suggested_action:
                  "Keep the original source and add the missing recipe details manually.",
                request_id: crypto.randomUUID(),
              };
            }
          }
        }
      }

      const { data: saved, error: saveError } = await admin.from(
        "recipe_import_jobs",
      ).update({
        status: "completed",
        stage: "done",
        recipe_id: result.recipe_id,
        recipe_status: result.status,
        review_count: result.review_fields.length,
        result,
        error: completionError,
        completed_at: now(),
        updated_at: now(),
      }).eq("id", jobID).eq("queue_message_id", queueID)
        .eq("status", "extracting").eq("attempt_count", claimedAttempt)
        .select("id")
        .maybeSingle();
      if (saveError || !saved) {
        throw saveError ?? new Error("Import state changed before save");
      }

      // Queue ACK is LAST. A worker crash before this line will replay a
      // completed job idempotently without creating a second recipe.
      await archive(queueID);
      completed++;
    } catch (error) {
      // Do not delete the message on failure. It becomes visible again and
      // the atomic claim RPC retries a stale lease at most three times.
      console.error("recipe_worker_process_failed", {
        msg_id: queueID,
        message: error instanceof Error ? error.message : "unknown",
      });
      deferred++;
    }
  }

  return Response.json({ completed, failed, deferred });

  async function archive(messageID: number): Promise<void> {
    const { data, error } = await admin.rpc(
      "recipe_import_v1_queue_archive",
      { p_msg_id: messageID },
    );
    if (error || data !== true) {
      throw error ?? new Error("Queue message was not archived");
    }
  }
});
