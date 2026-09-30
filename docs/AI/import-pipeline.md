# AI Import Pipeline

Input:
- URL
- text
- image
- video

Pipeline:

receive
→ source resolve
→ extract metadata
→ caption/article
→ ASR
→ OCR
→ vision evidence
→ recipe parser
→ validation
→ recipe

Rules:

- Never invent exact quantities.
- Preserve source evidence.
- Unknown values remain unknown.
- Low confidence fields require review.

Statuses:

received
queued
processing
completed
needs_review
failed
