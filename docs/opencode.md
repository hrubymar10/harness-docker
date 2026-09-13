# OpenCode

OpenCode is installed from the `opencode-ai` npm package. Set the
`OPENCODE_VERSION` image build argument to pin a release; an empty value installs
the package's current release. Image-level automatic updates are disabled so a
running container cannot drift from the built generation.

Run `opencode-docker`; arguments are forwarded after `--auto`. Integrations that
accept a CLI executable can use the absolute path to
`opencode-docker-vscode-wrapper`. The launcher exports `OPENCODE_SESSION_ID` and
uses the shared session cleanup and generation-pinning behavior.

Configuration defaults to `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`, while
authentication and data default to `${XDG_DATA_HOME:-$HOME/.local/share}/opencode`.
Override configuration with `OPENCODE_CONFIG_DIR` or `XDG_CONFIG_HOME`, and data
with `XDG_DATA_HOME`. The controller forwards only customized XDG variables,
does not change the container-wide XDG environment, requires absolute paths, and
mirrors both resulting directories.

Authenticate on the host with `opencode auth login` or provide a supported
provider key such as `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or
`MISTRAL_API_KEY`. The image supplies `opencode-session` and
`opencode-notifier` integration commands.
