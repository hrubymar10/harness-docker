# Codex CLI

Codex is installed from `@openai/codex`. Set the `CODEX_VERSION` image build
argument to pin a release; an empty value installs the package's current release.
The image supplies `codex-session` and `codex-notifier` integration commands.

Codex state defaults to `~/.codex` through `CODEX_HOME`. Authenticate on the host
with `codex login` or provide `OPENAI_API_KEY`, then mount only the state and
projects the sandbox may access.

Run `codex-docker`; arguments are forwarded after
`--dangerously-bypass-approvals-and-sandbox --no-daemon`, or after
`CODEX_LAUNCH_FLAGS` when that override is set. For VS Code, set
`chatgpt.cliExecutable` to the absolute path of
`codex-docker-vscode-wrapper`. The launcher exports `CODEX_SESSION_ID` and uses
the mounted `CODEX_HOME`.

`--no-daemon` keeps the container's Codex off the shared background app-server.
The host's Codex installs that daemon into `CODEX_HOME/packages` as a host
binary and talks to it over a socket in `CODEX_HOME`, so a container session that
tries to use it fails with `app server did not become ready`. Keep the flag in any
`CODEX_LAUNCH_FLAGS` override. Without the daemon, `codex agents` cannot browse
sessions that the host's daemon holds.

The package's expected `codex-path/rg` helper is intentionally a symlink to the
image's Alpine `/usr/bin/rg` (ripgrep 15.1.0 in the current base repositories).
Using the system binary avoids the incompatible bundled helper on Alpine while
preserving the path Codex invokes. The image build runs that exact symlink with
`--version`, so a missing or unusable helper fails the build.
