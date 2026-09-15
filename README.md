# harness-docker

Run Claude Code, Codex CLI, pi, Mistral Vibe, and OpenCode in one shared Docker
sandbox. Host paths, user identity, shell, Git configuration, and normal Docker
Compose workflows are mirrored closely enough that each harness still feels
native.

This is an opinionated daily-driver safety net for bad prompts, not bad actors.
It reduces accidental damage without claiming to contain deliberately hostile
code. Do not mount sensitive data or expose Docker access when adversarial-code
isolation is required. See [Security](docs/security.md) and
[accepted security issues](SECURITY_ISSUES.md).

## Supported harnesses

| Harness | Launcher | Guide |
| --- | --- | --- |
| Claude Code | `claude-docker` | [Claude Code](docs/claude-code.md) |
| Codex CLI | `codex-docker` | [Codex](docs/codex.md) |
| pi | `pi-docker` | [pi](docs/pi.md) |
| Mistral Vibe | `vibe-docker` | [Mistral Vibe](docs/vibe.md) |
| OpenCode | `opencode-docker` | [OpenCode](docs/opencode.md) |

## Quick start

Requirements are macOS or Linux on amd64 or arm64, Docker Compose v2, and host
authentication for at least one harness. Go is needed only to build the optional
beeper locally.

```bash
export PATH="/path/to/harness-docker/bin:$PATH"
cp config/docker-compose.local.example.yml config/docker-compose.local.yml
# Edit the local file to mount only the project roots the sandbox may access.
harness-docker-ctrl start
harness-docker-ctrl status
codex-docker
```

Launch from a mounted working directory. Arguments are forwarded to the selected
harness. Use `harness-docker-ctrl shell`, `exec`, `rebuild`, `gc`, or `stop` for
shared lifecycle operations. Read [Setup](docs/setup.md) before first use.
`rebuild` refreshes the harness CLIs while reusing cached base layers; pass
`--no-cache` for a full rebuild. Successful builds also tag the image as
`harness-docker:latest` for direct external runs.

## Documentation

- [Setup and host integration](docs/setup.md)
- Harnesses: [Claude Code](docs/claude-code.md), [Codex](docs/codex.md),
  [pi](docs/pi.md), [Mistral Vibe](docs/vibe.md), and
  [OpenCode](docs/opencode.md)
- [Session lifecycle](docs/lifecycle.md)
- [Generations and zero-downtime rebuilds](docs/generations.md)
- [Updates](docs/updates.md)
- [Security model and known limitations](docs/security.md)
- [AWS credential proxy](docs/aws.md)
- [GPG signing](docs/gpg.md)
- [Beeper and notifications](docs/notifications.md)
- [Migration from the standalone stacks](docs/migration.md)
- [Development and testing](docs/development.md)

## Supersedes

This repository replaces the separate `claude-docker`, `codex-docker`,
`pi-docker`, and `vibe-docker` repositories with one image, lifecycle, security
policy, and set of host integrations. Existing launcher names remain unchanged.
See the [migration guide](docs/migration.md) before retiring an old stack.

## License

See [LICENSE](LICENSE).
