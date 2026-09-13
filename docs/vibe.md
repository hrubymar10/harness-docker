# Mistral Vibe

Mistral Vibe is installed as the `mistral-vibe` Python tool. Set the
`VIBE_VERSION` image build argument to pin a release; an empty value installs the
package's current release. The image supplies `vibe-session` and
`vibe-notifier` integration commands.

Vibe state defaults to `~/.vibe`. Authenticate with Vibe's `/login` flow or
provide `MISTRAL_API_KEY`. Treat the mounted state and provider key as readable
by all processes in the sandbox.

Launcher and editor commands are documented when the host launchers are added.
