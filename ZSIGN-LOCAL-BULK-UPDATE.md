# Local ZSign / Bulk Signing Update

This update keeps signing entirely on-device and adds a local bulk coordinator.

## Engine changes
- Added per-job ZSign parallelism instead of a process-global Swift execution gate.
- Multiple local IPA jobs can run concurrently without racing the old global parallel flag.
- Kept ZSign's existing intra-app parallel DAG signing.
- Added a bounded local worker pool; default worker count is derived from available CPU cores and capped at 4.
- Added `LocalBulkSignEngine` and `LocalBulkSignJob` for multi-IPA signing.
- Batch workers avoid stdout/stderr capture because those file descriptors are process-global.
- Batch failures are isolated; one IPA does not cancel the rest of the batch.

## Cache correctness / speed
- ZSign cache keys now include signing context: team, certificate fingerprint, provisioning profile hash, entitlements hash, bundle overrides and display/version overrides.
- This prevents an old signing tree from being incorrectly reused after the signing certificate/profile changes.
- Existing `.zsign_cache` incremental behavior remains enabled.

## UI
- Added a `Bulk` button beside `Sign IPA`.
- The existing document picker can select multiple IPAs.
- Bulk signing applies the current signing options and active certificate locally.
- Signed results are added to the local Signed history.
- Progress and completion are shown in the signing sheet.

No VPS/API signing path was added.
