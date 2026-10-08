// Developer: gengyun
// Purpose: Processes owner-scoped import queue messages without unsafe remote URL fetching.

import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { parseLocalText } from "./textEvidence.ts";

interface QueueMessage {
  msg_id: number;
  read_ct: number;
  message: { job_id?: string; owner_id?: string; contract_version?: number };
}

interface Job {
  id: string;
  owner_id: string;
  input_type: "url" | "text";
  source_value: string;
  status: string;
  attempt_count: number;
  queue_message_id: number | null;
  updated_at: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
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
    "recipe_import_queue_read",
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

      if (claimed.input_type === "url") {
        // URL fetching remains explicitly disabled until the server has
        // DNS-pinned/per-redirect SSRF controls and source rights reviewed.
        const { data: stored, error } = await admin.from("recipe_import_jobs")
          .update({
            status: "failed",
            stage: "done",
            error: {
              code: "UNSUPPORTED_SOURCE",
              message:
                "Server-side webpage or video extraction is not yet available.",
              recoverable: false,
              suggested_action:
                "Paste the recipe text or use the app's local webpage import.",
              request_id: crypto.randomUUID(),
            },
            completed_at: now(),
            updated_at: now(),
          }).eq("id", jobID).eq("queue_message_id", queueID)
          .eq("status", "extracting").eq("attempt_count", claimedAttempt)
          .select("id")
          .maybeSingle();
        if (error || !stored) {
          throw error ?? new Error("Import state changed before save");
        }
        await archive(queueID);
        failed++;
        continue;
      }

      const result = parseLocalText({
        id: claimed.id,
        source_value: claimed.source_value,
      });
      const { data: saved, error: saveError } = await admin.from(
        "recipe_import_jobs",
      ).update({
        status: "completed",
        stage: "done",
        recipe_id: result.recipe_id,
        recipe_status: result.status,
        review_count: result.review_fields.length,
        result,
        error: null,
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
    const { error } = await admin.rpc(
      "recipe_import_queue_archive",
      { p_msg_id: messageID },
    );
    if (error) throw error;
  }
});
