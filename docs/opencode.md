# OpenCode

OpenCode is installed from the `opencode-ai` npm package. Set the
`OPENCODE_VERSION` image build argument to pin a release; an empty value installs
the package's current release. Image-level automatic updates are disabled so a
running container cannot drift from the built generation.

Run `opencode-docker`; arguments are forwarded after `--auto`, or after
`OPENCODE_LAUNCH_FLAGS` when that override is set. Integrations that accept a
CLI executable can use the absolute path to
`opencode-docker-vscode-wrapper`. The launcher exports `OPENCODE_SESSION_ID` and
uses the shared session cleanup and generation-pinning behavior.

Configuration defaults to `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`, while
authentication and data default to `${XDG_DATA_HOME:-$HOME/.local/share}/opencode`.
Override configuration with `OPENCODE_CONFIG_DIR` or `XDG_CONFIG_HOME`, and data
with `XDG_DATA_HOME`. The controller forwards only customized XDG variables,
does not change the container-wide XDG environment, requires absolute paths, and
mirrors both resulting directories.

A program that runs OpenCode once per turn can configure it for that session
through the environment (`OPENCODE_CONFIG_CONTENT`, `OPENCODE_DB`,
`XDG_CONFIG_HOME`, and the `OPENCODE_DISABLE_*` switches) by listing the names in
`HARNESS_DOCKER_FORWARD_ENV`; see [Session lifecycle](lifecycle.md). It should
also set `OPENCODE_LAUNCH_FLAGS=` (empty): the built-in `--auto` comes before the
subcommand, so `opencode --auto run ...` starts the interactive interface
instead of `run`, and the program passes its own flags after `run`.

Authenticate on the host with `opencode auth login` or provide a supported
provider key such as `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or
`MISTRAL_API_KEY`. The image supplies `opencode-session` and
`opencode-notifier` integration commands.
