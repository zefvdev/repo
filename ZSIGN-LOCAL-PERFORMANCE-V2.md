# Local ZSign Performance V2

mSign's signing engine remains entirely on-device. This update adds the next performance layer around the existing in-process ZSign engine.

## Included optimizations

1. **Persistent batch workspace** — one batch root is reused for job workspaces instead of creating unrelated temporary roots for every job.
2. **Bounded adaptive concurrency** — worker count considers CPU cores, physical memory, and the fact that ZSign already parallelizes independent bundle nodes.
3. **Content-addressed result cache** — identical IPA + certificate/profile + password + signing options can return a previously produced signed IPA without repeating extraction/signing/packaging.
4. **Shared signing context** — P12 and provisioning profile are staged once per batch and reused read-only by all workers.
5. **Hash reuse** — the cache key streams the IPA in 1 MiB chunks and hashes the signing context/options once for the job.
6. **Fast packaging** — fast mode uses stored ZIP entries; balanced/maximum modes remain available through `SigningCompressionMode`.
7. **Reduced redundant certificate/profile work** — bulk workers reuse the same staged signing files instead of rewriting them for every IPA.
8. **Batch-level statistics** — completed count, cache hits, failures, and elapsed time are exposed to the UI.
9. **Incremental component signing remains enabled** — the existing ZSign `.zsign_cache` and internal signing DAG are preserved.
10. **Minimal Swift/C++ boundary overhead** — bulk workers call the existing in-process ZSign bridge directly; no shell process or network API is introduced.

## Safety

- Dylib mutation retains the existing conservative parallel-signing behavior.
- Console stdout/stderr capture is not used concurrently by bulk workers because those streams are process-global.
- Cache keys include the source IPA, signing material, password hash input, and signing configuration, so a changed signing context does not reuse an old result.
- The result cache is capped at 2 GiB and trims oldest entries when necessary.
