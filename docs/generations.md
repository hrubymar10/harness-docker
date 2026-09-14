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

Each session owns a PID directory associated with its generation. Retirement and
`harness-docker-ctrl gc` remove an old Compose project only after stale PID
records have been cleaned and no live session remains. This is the core
blue-green invariant: a rebuild may change the destination for new work but must
not interrupt active work.

`restart` has intentionally different semantics: it stops every generation
before starting a fresh one. Use it when zero-downtime handoff is not required.
