# Mistral Vibe

Mistral Vibe is installed as the `mistral-vibe` Python tool. Set the
`VIBE_VERSION` image build argument to pin a release; an empty value installs the
package's current release. The image supplies `vibe-session` and
`vibe-notifier` integration commands.

Vibe state defaults to `~/.vibe`. Authenticate with Vibe's `/login` flow or
provide `MISTRAL_API_KEY`. Treat the mounted state and provider key as readable
by all processes in the sandbox.

Run `vibe-docker`; arguments are forwarded after `--yolo`, or after
`VIBE_LAUNCH_FLAGS` when that override is set. Integrations that accept a CLI
executable can use the absolute path to
`vibe-docker-vscode-wrapper`. The launcher exports `VIBE_SESSION_ID` and uses
the mounted `VIBE_HOME`.
