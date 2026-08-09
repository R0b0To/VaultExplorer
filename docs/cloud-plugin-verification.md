# Cloud plugin verification checklist

Use a release build of both VaultExplorer and VaultSync Bridge signed with the
expected certificates. Record device, Android version, provider, network type,
vault size, and cold/warm cache state with every result.

## Functional release gate

- [ ] With VaultSync Bridge uninstalled, **Mount cloud vault** explains that the
      plugin is unavailable; local containers and USB mounts still work.
- [ ] Add an account in Bridge, then list it from VaultExplorer. Remove the
      account and confirm its credentials and cached chunks are no longer usable.
- [ ] Discover a converted vault, unlock it with a correct password, browse it,
      create/edit/delete a file, relock, and verify the change from a second
      client or after remounting.
- [ ] Wrong password and unsupported/corrupt manifest fail without mounting or
      retaining a password in logs, saved records, or intent extras.
- [ ] A sparse converted range reads as zeroes and does not cause a provider
      download; inspect the Bridge's request log or provider telemetry.
- [ ] Make a 5 KB edit inside a large vault and verify exactly the affected 4 MB
      chunk is staged, finalized, and uploaded.
- [ ] Disable network or revoke the OAuth token while mounted. The Bridge
      invalidation callback must lock the matching VaultExplorer session and
      leave no AppFuse descriptor/session registration behind.
- [ ] Repeat the mount after process death, device rotation, and app restart;
      no duplicate service bindings, leaked file descriptors, or stale cache
      data may be observed.

## Performance targets

| Scenario | Target | How to measure |
| --- | --- | --- |
| Header read / password prompt | < 1.5 s | Cold read of chunk 0 over each supported provider. |
| Random media read | < 300 ms cached; < 2.5 s miss | Record p50/p95 for 4 MB chunk fetches while browsing photos/video. |
| Small write | < 2 s | Edit a 5 KB file in a 20 GB cloud vault; verify one chunk upload. |
| Sparse read | 0 network calls | Read unallocated/sparse range while tracing provider requests. |
| Disconnect safety | Immediate lock | Revoke token or drop network and time lock notification/cleanup. |
| Offline independence | No regression | Mount local `.hc` and USB volumes with Bridge absent. |

Run each performance case at least five times for cold and warm cache. Report
median and p95, not only the best run. Treat a target miss as a profiling task:
capture chunk-cache hit rate, provider latency, file-descriptor lifetime, and
native `disk_read`/`disk_write` timing before changing the transport path.

## Automated checks included in this change

- `:app:compileDebugKotlin` for VaultExplorer and `:app:compileFossDebugKotlin`
  for VaultSync Bridge compile the AIDL boundary and both Android clients.
- `chunked_block_device_test` covers cross-chunk range splitting, callback
  failure propagation, and EOF/overflow guards. Configure a host CMake build
  (non-Android) and run `ctest --output-on-failure`.
- Targeted Dart analysis covers the cloud unlock flow, dashboard entry, API
  callback registration, and saved cloud-record routing.
