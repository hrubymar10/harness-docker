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
specific configuration belongs in ignored files under `config/`. Copy
[`config/.env.example`](../config/.env.example) to the ignored `config/.env`
only when automatic host detection needs an override.

## Harness state and authentication

The controller creates missing state directories. Defaults and overrides are:

| Harness | Host directory | Override |
| --- | --- | --- |
| Claude Code | `~/.claude` | `CLAUDE_CONFIG_DIR` |
| Codex CLI | `~/.codex` | `CODEX_HOME` |
| pi | `~/.pi/agent` | `PI_CODING_AGENT_DIR` |
| Mistral Vibe | `~/.vibe` | `VIBE_HOME` |
| OpenCode config | `~/.config/opencode` | `OPENCODE_CONFIG_DIR` or `XDG_CONFIG_HOME` |
| OpenCode auth/data | `~/.local/share/opencode` | `XDG_DATA_HOME` |

Authenticate only the harnesses you use on the host: run `claude`, `codex
login`, pi or Vibe's `/login` flow, or provide the relevant provider API key.
OpenCode authenticates with `opencode auth login` or provider keys. Unused
harness directories may remain empty. GitHub/GitLab CLI tokens, Git
identity, Go settings, UID, home, and shell are detected where possible.

Claude's legacy single-file configuration cannot be updated safely through a
Docker Desktop file bind. Quit Claude processes, move `~/.claude.json` to
`~/.claude/.claude.json`, and persist
`CLAUDE_CONFIG_DIR="$HOME/.claude"`. Startup refuses the unsafe legacy layout.
`PI_PACKAGE_DIR` may select a separate pi package directory. Every configured
path must be absolute. OpenCode follows its XDG defaults without modifying the
container-wide XDG environment; only customized XDG variables are forwarded.

## Building the image

The Alpine-based image installs Docker tooling, Git, GitHub and GitLab CLIs,
AWS CLI, Go, Node.js tooling, Python tooling, debuggers, language servers, and
the five supported harnesses. Build arguments include `GO_VERSION`,
`CC_VERSION`, `CODEX_VERSION`, `PI_VERSION`, `VIBE_VERSION`,
`OPENCODE_VERSION`, and extra Alpine, npm, Go, and Python package lists. Pinning
a harness version makes builds reproducible; empty harness-version values select
the upstream current release.

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

The local file's `x-excludes` list masks selected files with `/dev/null` and
directories with empty read-only tmpfs mounts. Use it for secrets nested below a
mounted project root. It is a visibility guard inside this stack, not a promise
that hostile code cannot reach other exposed interfaces.

The Compose stack mounts harness state read-write, `gpg-keys/` and custom tools
read-only, and the Docker socket only into the socket proxy. Use the memory-limit
setting where desired. Docker Desktop and Docker Engine reach host helpers via
`host.docker.internal` and the configured host-gateway mapping.

## Starting the stack

Put the repository's `bin/` directory on `PATH`, then run
`harness-docker-ctrl start`. The controller checks Docker compatibility,
bootstraps missing local configuration and state directories, derives the bind
allowlist, builds when necessary, and starts the current generation. Use
`harness-docker-ctrl status` to inspect it.
