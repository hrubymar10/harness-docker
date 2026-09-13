# pi

pi is installed from `@earendil-works/pi-coding-agent` with package install
scripts disabled. Set the `PI_VERSION` image build argument to pin a release; an
empty value installs the package's current release. The image supplies
`pi-session` and `pi-notifier` integration commands.

pi state defaults to `~/.pi/agent`. Authenticate with pi's `/login` flow or use
the provider keys supported by your configuration. A separate package directory
can be mounted when host and agent package state should not share a root.

Run `pi-docker`; its arguments are forwarded without an additional permission
flag. Integrations that accept a CLI executable can use the absolute path to
`pi-docker-vscode-wrapper`. The launcher exports `PI_SESSION_ID` and uses the
mounted `PI_CODING_AGENT_DIR` plus optional `PI_PACKAGE_DIR`.

Use `PI_PACKAGE_DIR` when packages should live outside the normal agent-state
directory. Both paths must be absolute and are readable by sandbox processes.
