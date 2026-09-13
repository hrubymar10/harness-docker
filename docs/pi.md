# pi

pi is installed from `@earendil-works/pi-coding-agent` with package install
scripts disabled. Set the `PI_VERSION` image build argument to pin a release; an
empty value installs the package's current release. The image supplies
`pi-session` and `pi-notifier` integration commands.

pi state defaults to `~/.pi/agent`. Authenticate with pi's `/login` flow or use
the provider keys supported by your configuration. A separate package directory
can be mounted when host and agent package state should not share a root.

Launcher and editor commands are documented when the host launchers are added.
