# Claude Code

Claude Code is installed in the shared image with the vendor installer. Set the
`CC_VERSION` image build argument to request a specific release; an empty value
keeps the installer's current release. The image supplies `claude-session` and
`claude-notifier` integration commands.

Claude state is expected under `~/.claude` or `CLAUDE_CONFIG_DIR`. Authenticate
on the host before mounting that state. Because sandbox processes can read and
modify it, use a dedicated account or limited credentials when appropriate.

Launcher and editor commands are documented when the host launchers are added.
