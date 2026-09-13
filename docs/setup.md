# Setup and host integration

The container entrypoint mirrors the invoking user's numeric UID and GID, home
path, login name, and shell. It creates the host home path in the container,
installs shared profile configuration, and runs the requested command as that
user. This keeps absolute project paths, Git ownership, and shell behavior
consistent across the host and sandbox.

The setup scripts also:

- assemble `PATH` from system tools, the repository launchers, custom binaries,
  language toolchains, and the selected harness;
- copy supported host Git and CLI credential configuration into the sandbox
  user's home when those inputs are mounted;
- install the guarded `git` command while leaving the deliberately explicit real
  binary available for manual bypass; and
- preserve interactive terminals while keeping piped and editor-driven commands
  stream-safe.

Only mount paths and configuration that sandboxed processes may read. Machine
specific configuration belongs in ignored files under `config/`.
