# harness-docker

`harness-docker` runs supported coding-agent harnesses inside a shared Docker sandbox with host path mirroring, Docker socket filtering, and safety rails.

## Documentation discipline

- Before changing code, read the documentation the change touches.
- Keep `README.md` aligned with user-visible behavior and setup changes.
- When flags, environment variables, tool names, behavior, or supported harnesses
  change, update the affected documentation and the README supported-harness
  list in the same commit.
- Keep this file focused on durable repository conventions; `CLAUDE.md` must remain a symlink to it.
- Document security tradeoffs and compatibility behavior next to the code they affect.
- Ask before fixing an unrelated issue or otherwise widening the requested diff.
- Never include a person's name or a linkable issue reference in repository files or commit messages.

## Commit messages

- Use Conventional Commits: `type(scope): imperative summary`.
- Follow the subject with a blank line and a body explaining why the change is needed and any non-obvious consequences.
- Do not use title-only commits for behavioral, test, or documentation changes.
- Keep each commit focused on one coherent change.
- Commit with plain `git commit`. Never use `--author`, `GIT_AUTHOR_*`, or
  `GIT_COMMITTER_*`; author and committer must be identical. Do not add AI attribution.
- Do not push unless explicitly instructed.

## Testing

- Run `make lint` after changing shell scripts.
- Run `make test` after meaningful behavior changes.
- When compose or image behavior changes, also render the compose configuration and build the affected image.
- Preserve security defaults, host path mirroring, and interactive versus non-interactive behavior in tests.
- All tests must pass before committing; never commit a red tree.

## Dependencies

- Do not add, update, or remove Alpine packages, npm packages, Go modules, or
  other dependencies without explicit consent.
- First propose the package and version, why it is needed, and the associated risk.

## Project structure

- `bin/` — host-side launchers and lifecycle commands for the supported harnesses.
- `bin/lib/` — shell helpers shared by host-side commands.
- `scripts/` — shell scripts installed in or used by the container image.
- `docker/` — system configuration copied into the image.
- `docker-filter-proxy/` — Docker API validation layer in front of the socket proxy.
- `beeper/` — optional host-side HTTP notification server.
- `config/` — examples and gitignored local configuration.
- `gpg-keys/` — local signing keys; only its placeholder is committed.
- `test/` — host-side integration and regression tests.

Prefer small, direct shell scripts over heavy abstractions. Keep harness-specific behavior in harness-specific files and shared behavior in clearly named common helpers.

## Documentation map

- `README.md` — overview, supported-harness list, quick start, and topic index.
- `docs/setup.md` — prerequisites, host integration, state, mounts, and image setup.
- `docs/claude-code.md`, `docs/codex.md`, `docs/pi.md`, `docs/vibe.md` — harness-specific setup, launchers, flags, state, and editor integration.
- `docs/lifecycle.md` — launch and controller commands.
- `docs/generations.md` — rebuild, handoff, retirement, and garbage collection.
- `docs/updates.md` — default-branch checks and fast-forward updates.
- `docs/security.md` — threat model, defense layers, and known limitations.
- `docs/aws.md`, `docs/gpg.md`, `docs/notifications.md` — optional host integrations.
- `docs/migration.md` — transition from the standalone harness stacks.
- `docs/development.md` — repository layout and validation workflow.

## Generations model

- Treat the current-generation pointer as the atomic handoff for new sessions.
- Resolve a launcher to one immutable container ID; never retarget an active session after a rebuild.
- Start and health-check a replacement before switching the pointer. Retire old generations only after their session PID directories are empty.

## Update flow

- Passive checks may inspect the remote default branch but must not fetch or mutate the checkout.
- Updates require a clean checkout on the default branch and must be fast-forward only.
- Preserve and restore the prior branch and commit if an update fails; avoid update/re-exec loops.

## Security posture

- Optimize for preventing accidental damage from bad prompts, not containment of a malicious actor.
- Preserve the Docker wrapper, filter proxy, socket proxy, Git-push guard, canonical-path validation, and bind-mount allowlist as defense-in-depth layers.
- Keep server-side Git protection authoritative and document intentional bypasses and residual Docker API gaps.

## Design decisions

- Mirror host paths and identity so terminal, editor, Compose, debugger, and language-server workflows remain natural.
- Keep one shared image and lifecycle; define harness-specific binaries, session variables, wrappers, and flags in the common harness table.
- Prefer explicit, recoverable state transitions and fail-closed validation. Avoid hardening that breaks the intended daily workflow without a demonstrated risk reduction.

## Quick start

```bash
bin/harness-docker-ctrl start
bin/harness-docker-ctrl status
bin/harness-docker-ctrl shell
bin/harness-docker-ctrl exec
bin/harness-docker-ctrl stop
```

Use `config/docker-compose.local.yml` for machine-specific mounts and settings; keep local configuration out of version control.
