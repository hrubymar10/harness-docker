# Codex CLI

Codex is installed from `@openai/codex`. Set the `CODEX_VERSION` image build
argument to pin a release; an empty value installs the package's current release.
The image supplies `codex-session` and `codex-notifier` integration commands.

Codex state defaults to `~/.codex` through `CODEX_HOME`. Authenticate on the host
with `codex login` or provide `OPENAI_API_KEY`, then mount only the state and
projects the sandbox may access.

Launcher and editor commands are documented when the host launchers are added.
