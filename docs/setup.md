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

## Building the image

The Alpine-based image installs Docker tooling, Git, GitHub and GitLab CLIs,
AWS CLI, Go, Node.js tooling, Python tooling, debuggers, language servers, and
the four supported harnesses. Build arguments include `GO_VERSION`,
`CC_VERSION`, `CODEX_VERSION`, `PI_VERSION`, `VIBE_VERSION`, and extra Alpine,
npm, Go, and Python package lists. Pinning a harness version makes builds
reproducible; empty harness-version values select the upstream current release.

Extra package lists execute during image build and are trusted inputs. Review
them as dependency changes before enabling them.

## Compose configuration

`docker-compose.yml` defines three cooperating services: the harness, the
request-validating filter proxy, and the method/path-limiting socket proxy. The
harness receives the host UID, login name, home path, shell, Git identity,
provider tokens, Go settings, and harness state paths through environment
variables.

Copy `config/docker-compose.local.example.yml` to
`config/docker-compose.local.yml` and mount
only the project roots needed for work. Keep the same absolute paths inside and
outside the container so editors, Git, Compose, and debuggers agree. Local
overrides may also add resources or GPU access without changing the shared file.

The Compose stack mounts harness state read-write, `gpg-keys/` and custom tools
read-only, and the Docker socket only into the socket proxy. Use the memory-limit
setting where desired. Docker Desktop and Docker Engine reach host helpers via
`host.docker.internal` and the configured host-gateway mapping.
