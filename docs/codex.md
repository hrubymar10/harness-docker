# Codex CLI

Codex is installed from `@openai/codex`. Set the `CODEX_VERSION` image build
argument to pin a release; an empty value installs the package's current release.
The image supplies `codex-session` and `codex-notifier` integration commands.

Codex state defaults to `~/.codex` through `CODEX_HOME`. Authenticate on the host
with `codex login` or provide `OPENAI_API_KEY`, then mount only the state and
projects the sandbox may access.

Run `codex-docker`; arguments are forwarded after
`--dangerously-bypass-approvals-and-sandbox`, or after `CODEX_LAUNCH_FLAGS` when
that override is set. For VS Code, set
`chatgpt.cliExecutable` to the absolute path of
`codex-docker-vscode-wrapper`. The launcher exports `CODEX_SESSION_ID` and uses
the mounted `CODEX_HOME`.

The package's expected `codex-path/rg` helper is intentionally a symlink to the
image's Alpine `/usr/bin/rg` (ripgrep 15.1.0 in the current base repositories).
Using the system binary avoids the incompatible bundled helper on Alpine while
preserving the path Codex invokes. The image build runs that exact symlink with
`--version`, so a missing or unusable helper fails the build.
