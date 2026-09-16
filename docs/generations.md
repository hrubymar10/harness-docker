# Generations and rebuilds

Each deployment is a Compose project with an immutable generation name. A small
current-generation pointer chooses the container used by new terminal and editor
sessions. A launcher resolves that pointer once and pins the resulting container
ID for the entire session; a later rebuild never retargets a running harness.

`harness-docker-ctrl rebuild` builds and starts a replacement, waits for its
health checks, then atomically switches the pointer. Existing sessions remain on
the retired generation and new sessions enter the replacement. Rebuilds reuse
cached base-image layers by default while refreshing all harness CLI installs.
Pass `--no-cache` to rebuild every image layer from scratch.

Each session has a host-side heartbeat under
`config/.generations/<generation>/<session-id>.hb`. The detached session
watchdog creates it before launch and refreshes it every 15 seconds while the
launcher's exact process identity remains alive. A heartbeat is live for 60
seconds after its last refresh, so a force-quit or host crash eventually makes
the session eligible for collection without relying on state inside the
container.

Automatic cleanup and `harness-docker-ctrl gc` discover generations from their
Compose project labels. They always protect the current pointer and any
non-current generation with a live heartbeat; every other non-current Compose
project is removed. This is the core blue-green invariant: a rebuild may change
the destination for new work but must not interrupt active work, while abandoned
generations are reclaimed after their final heartbeat expires. `status` reports
each generation's live-session count and newest heartbeat age.

`restart` has intentionally different semantics: it stops every generation
before starting a fresh one. Use it when zero-downtime handoff is not required.
