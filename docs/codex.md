# Codex CLI

Codex is installed from `@openai/codex`. Set the `CODEX_VERSION` image build
argument to pin a release; an empty value installs the package's current release.
The image supplies `codex-session` and `codex-notifier` integration commands.

Codex state defaults to `~/.codex` through `CODEX_HOME`. Authenticate on the host
with `codex login` or provide `OPENAI_API_KEY`, then mount only the state and
projects the sandbox may access.

Run `codex-docker`; arguments are forwarded after
`--dangerously-bypass-approvals-and-sandbox`. For VS Code, set
`chatgpt.cliExecutable` to the absolute path of
`codex-docker-vscode-wrapper`. The launcher exports `CODEX_SESSION_ID` and uses
the mounted `CODEX_HOME`.
