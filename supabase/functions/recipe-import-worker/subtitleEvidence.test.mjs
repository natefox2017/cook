// Developer: gengyun
// Purpose: Exercise original synthetic WebVTT evidence and public-page text compatibility offline.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { attachOwnerUploadedWebVTT, webVTTText } from "./subtitleEvidence.ts";
import { decodePlainTextArtifact } from "./artifactText.ts";

const original = readFileSync(new URL("./fixtures/owner-synthetic-subtitles.vtt", import.meta.url), "utf8");
const base = () => ({
  recipe_id: "synthetic-job",
  status: "needs_review",
  source: { input_type: "file", source_artifact_id: "synthetic-owner-artifact", original_url: null },
  fields: {},
  evidence: [{ id: "existing", excerpt: "Original owner source" }],
  review_fields: ["ingredients", "steps"],
});
const attach = (text, options = {}, result = base()) => attachOwnerUploadedWebVTT(result, {
  text, authorizationReference: "owner-fixture-dev78", sourceDurationSeconds: 12, ...options,
});
const cue = (timing = "00:00.000 --> 00:01.000", text = "salt to taste") =>
  `WEBVTT\n\n${timing}\n${text}\n`;

test("owner fixture bytes pass the existing strict decoder before the subtitle adapter", async () => {
  const bytes = readFileSync(new URL("./fixtures/owner-synthetic-subtitles.vtt", import.meta.url));
  let adapterCalls = 0;
  const decodeAndAttach = async (blob, expectedBytes) => {
    const text = await decodePlainTextArtifact(blob, expectedBytes);
    adapterCalls++;
    return attach(text);
  };
  const result = await decodeAndAttach(new Blob([bytes]), bytes.length);
  assert.equal(result.evidence.length, 4);
  assert.equal(result.evidence[1].excerpt, "Ingredients\nsalt to taste & a little butter");
  assert.equal(adapterCalls, 1);
  const invalidUTF8 = new Blob([Uint8Array.of(0xc3, 0x28)]);
  await assert.rejects(() => decodeAndAttach(invalidUTF8, invalidUTF8.size),
    { code: "ARTIFACT_INVALID_TEXT" });
  await assert.rejects(() => decodeAndAttach(new Blob([bytes]), bytes.length + 1),
    { code: "ARTIFACT_TOO_LARGE" });
  assert.equal(adapterCalls, 1, "Rejected bytes never enter the subtitle adapter");
});

test("synthetic owner captions preserve exact text, timestamps, uncertainty and existing data", () => {
  const input = base();
  const before = JSON.stringify(input);
  const result = attach(original, {}, input);
  assert.equal(JSON.stringify(input), before);
  assert.deepEqual(result.fields, {});
  assert.deepEqual(result.source, input.source);
  assert.equal(result.status, "needs_review");
  assert.deepEqual(result.review_fields, ["ingredients", "steps", "media_evidence_requires_review"]);
  assert.deepEqual(result.evidence[0], input.evidence[0]);
  assert.equal(result.evidence.length, 4);
  const segments = result.evidence.slice(1);
  assert.deepEqual(segments.map(({ timestamp_start_seconds, timestamp_end_seconds }) =>
    [timestamp_start_seconds, timestamp_end_seconds]), [[0, 4.25], [4.25, 9], [9, 12]]);
  assert.equal(segments[0].excerpt, "Ingredients\nsalt to taste & a little butter");
  for (const segment of segments) {
    assert.equal(segment.source_type, "subtitle");
    assert.equal(segment.origin, "owner_uploaded");
    assert.equal(segment.confidence, null);
    assert.ok(segment.id);
  }
  assert.equal(new Set(segments.map(({ id }) => id)).size, 3);
});

test("BOM, CRLF, hours, cue IDs/settings, entity and markup handling remain readable", () => {
  const text = "\uFEFFWEBVTT example\r\n\r\ncue-1\r\n00:01:00.100 --> 00:01:02.500 position:50%\r\n<v Chef>Use &#x26; &#38; &lt; &gt; &quot; &apos; &nbsp;.</v>\r\n";
  const result = attach(text, { sourceDurationSeconds: 63 });
  assert.equal(result.evidence[1].timestamp_start_seconds, 60.1);
  assert.equal(result.evidence[1].timestamp_end_seconds, 62.5);
  assert.equal(result.evidence[1].excerpt, 'Use & & < > " \' .');
  assert.equal(webVTTText(text), 'Use & & < > " \' .');
});

test("public-page text retains prior flattening, consecutive dedupe and bounded output", () => {
  assert.equal(webVTTText(original), "Ingredients\nsalt to taste & a little butter\nSteps\nStir gently.\nDo not infer a cooking time or an exact amount.");
  assert.equal(webVTTText("WEBVTT\n\n00:00.000 --> 00:01.000\nHello\nHello\n\n00:01.000 --> 00:02.000\nHello\nWorld"), "Hello\nWorld");
  assert.equal(webVTTText("plain source without header"), "plain source without header");
  assert.equal(webVTTText(cue(undefined, "x".repeat(11_000))).length, 10_000);
});

test("dedupe comes from the existing media helper; ready fields are never replaced", () => {
  const text = cue() + "\n00:00.000 --> 00:01.000\nsalt to taste\n";
  const ready = { ...base(), status: "ready", review_fields: [], fields: { title: { user_confirmed: true } } };
  const result = attach(text, {}, ready);
  assert.equal(result.evidence.length, 2);
  assert.equal(result.status, "ready");
  assert.deepEqual(result.review_fields, []);
  assert.deepEqual(result.fields, ready.fields);
});

test("invalid times, duration, SRT and malformed cues fail closed without modifying input", () => {
  const inputs = [
    "", "WEBVTT", "1\n00:00:00,000 --> 00:00:01,000\nSalt",
    cue("00:02.000 --> 00:01.000"), cue("00:01.000 --> 00:01.000"),
    cue("00:60.000 --> 01:01.000"), cue("00:00.000 --> 00:13.000"),
    cue("NaN --> Infinity"), cue("-00:01.000 --> 00:02.000"),
    cue("00:00.000 --> 00:01.000", ""),
    "WEBVTT\n00:00.000 --> 00:01.000\nSalt",
    cue() + "00:01.000 --> 00:02.000\nSugar",
    "WEBVTT\n\nnot a cue\n", cue(undefined, "\0"),
    "WEBVTT --> invalid\n\n00:00.000 --> 00:01.000\nSalt",
    cue("00:02.000 --> 00:03.000") + "\n00:00.000 --> 00:01.000\nButter",
  ];
  const input = base();
  const before = JSON.stringify(input);
  for (const text of inputs) assert.throws(() => attach(text, {}, input));
  for (const duration of [0, -1, NaN, Infinity, 3601]) {
    assert.throws(() => attach(original, { sourceDurationSeconds: duration }, input));
  }
  assert.equal(JSON.stringify(input), before);
});

test("source, per-cue, cue-count and total budgets reject oversized input", () => {
  assert.throws(() => attach("WEBVTT\n\n" + "x".repeat(100_000)));
  assert.throws(() => attach(cue(undefined, "x".repeat(1501))));
  const repeats = (count, text) => "WEBVTT\n\n" +
    Array.from({ length: count }, () => `00:00.000 --> 00:01.000\n${text}\n\n`).join("");
  assert.equal(attach(repeats(60, "salt")).evidence.length, 2);
  assert.throws(() => attach(repeats(61, "salt")));
  assert.throws(() => attach(repeats(14, "x".repeat(1500))));
  assert.throws(() => attach(original, { authorizationReference: "" }));
});
