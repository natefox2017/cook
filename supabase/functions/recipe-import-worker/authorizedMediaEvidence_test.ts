// Purpose: Deny unauthorized or malformed media and prevent invented recipe fields.

import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { attachAuthorizedMediaEvidence } from "./authorizedMediaEvidence.ts";
import type { ParsedWebRecipe } from "./schemaRecipe.ts";

const base = (): ParsedWebRecipe => ({
  recipe_id: "123e4567-e89b-12d3-a456-426614174000",
  status: "needs_review",
  source: {
    input_type: "url",
    original_url: "https://recipes.example/video",
    canonical_url: "https://recipes.example/video",
    platform: null,
    author_name: null,
    source_title: null,
  },
  fields: {},
  evidence: [],
  review_fields: ["ingredients", "steps"],
});

Deno.test("permitted owner transcript records exact evidence without inventing fields", () => {
  const result = attachAuthorizedMediaEvidence(base(), {
    authorizationMethod: "owner_uploaded",
    authorizationReference: "verified-upload-001",
    sourceDurationSeconds: 60,
    segments: [{
      kind: "audio_transcript",
      excerpt: "Use some butter.",
      startSeconds: 8,
      endSeconds: 12,
      confidence: 0.8,
    }],
  });
  assertEquals(result.fields, {});
  assertEquals(result.status, "needs_review");
  assertEquals(result.evidence.length, 1);
  assertEquals(result.evidence[0].timestamp_start_seconds, 8);
  assertEquals(result.evidence[0].timestamp_end_seconds, 12);
  assertEquals(result.evidence[0].origin, "owner_uploaded");
  assertEquals(result.review_fields.includes("media_evidence_requires_review"), true);
});

Deno.test("no public-client authorization string or oversized audio is accepted", () => {
  assertThrows(() => attachAuthorizedMediaEvidence(base(), {
    authorizationMethod: "owner_uploaded",
    authorizationReference: "",
    sourceDurationSeconds: 60, segments: [{kind:"subtitle",excerpt:"Hello",startSeconds:0,endSeconds:5}],
  }));
  assertThrows(() => attachAuthorizedMediaEvidence(base(), {
    authorizationMethod: "owner_uploaded",
    authorizationReference: "verified-upload-001",
    sourceDurationSeconds: 9_000, segments: [{kind:"subtitle",excerpt:"Hello",startSeconds:0,endSeconds:5}],
  }));
});

Deno.test("invalid timestamps and confidence fail closed", () => {
  assertThrows(() => attachAuthorizedMediaEvidence(base(), {
    authorizationMethod: "approved_public_api",
    authorizationReference: "approved-api-001",
    sourceDurationSeconds: 100, segments: [{kind:"keyframe_text",excerpt:"Olive oil",startSeconds:101,endSeconds:102}],
  }));
  assertThrows(() => attachAuthorizedMediaEvidence(base(), {
    authorizationMethod: "approved_public_api",
    authorizationReference: "approved-api-001",
    sourceDurationSeconds: 100, segments: [{kind:"subtitle",excerpt:"Olive oil",startSeconds:1,endSeconds:2,confidence:3}],
  }));
});

Deno.test("deduplicates equivalent media segments and preserves ready status", () => {
  const ready = {...base(), status: "ready" as const, review_fields: []};
  const segment = {kind: "subtitle" as const, excerpt: "500 ml water", startSeconds: 2, endSeconds: 3};
  const result = attachAuthorizedMediaEvidence(ready, {
    authorizationMethod: "approved_public_api",
    authorizationReference: "verified-caption-002",
    sourceDurationSeconds: 30, segments: [segment,segment],
  });
  assertEquals(result.evidence.length,1);
  assertEquals(result.status,"ready");
  assertEquals(result.review_fields,[]);
});
