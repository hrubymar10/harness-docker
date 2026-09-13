# Session lifecycle

Run a harness launcher from a working directory that is mounted at the same
absolute path inside the Compose service. The shared launch code resolves the
current generation once, validates the working directory against the container's
bind mounts, and pins one immutable container ID for the session.

Interactive callers receive a TTY. Piped commands and editor wrappers keep
stdin/stdout stream-safe. Arguments after the launcher are forwarded to the
harness, and session PID bookkeeping is removed on normal exit or signals.

The launchers are `claude-docker`, `codex-docker`, `pi-docker`, and
`vibe-docker`. Matching `*-docker-vscode-wrapper` commands provide an executable
path for editor integrations. Lifecycle controller commands are documented when
the controller is added.
