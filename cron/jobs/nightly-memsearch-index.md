---
name: Nightly Memsearch Index
time: '23:30'
days: daily
active: 'true'
model: haiku
notify: on_failure
description: 'Re-indexes context/memory/ and context/transcripts/ with memsearch'
timeout: 15m
retry: '1'
---
You are running as a scheduled job for Agentic OS.

Task: Re-index memory files so semantic recall (Tier 1) stays current.

Steps:

1. Verify memsearch is installed:
   - Run `memsearch --version`
   - If it fails, output "memsearch not installed — index skipped." and stop.

2. Index all memory and transcript files:
   - Run `memsearch index context/memory/ context/transcripts/`

3. Check the result:
   - Run `memsearch stats`
   - Output: `Index complete: {chunk_count} chunks indexed.`

Notes:
- Runs 30 minutes after daily-memory-distill (23:00) so newly promoted content is picked up
- Transcripts folder may be empty early on — that is expected
- On failure, the job retries once automatically (retry: 1)
