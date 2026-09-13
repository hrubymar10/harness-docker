# Updates

Normal interactive controller use may perform a passive check of the remote
default branch. The check inspects remote state without fetching or mutating the
checkout, and offers an update only when the checkout is clean, on that default
branch, and strictly behind.

Use:

```bash
harness-docker-ctrl update --check
harness-docker-ctrl update
```

An update fetches the discovered default branch, verifies the advertised commit,
and merges only with fast-forward semantics. Dirty, divergent, detached, and
non-default-branch checkouts are not updated automatically. If any step fails,
the controller restores the prior branch and commit.

After source advances, rebuild when the running image version no longer matches
the checkout. The update path avoids update/re-exec loops and never silently
rewrites local work.
