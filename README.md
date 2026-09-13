# harness-docker

Shared foundations for running coding-agent harnesses in a Docker sandbox. The
shared image contains four supported harnesses:

| Harness | Documentation |
| --- | --- |
| Claude Code | `claude-docker` · [Claude Code](docs/claude-code.md) |
| Codex CLI | `codex-docker` · [Codex](docs/codex.md) |
| pi | `pi-docker` · [pi](docs/pi.md) |
| Mistral Vibe | `vibe-docker` · [Mistral Vibe](docs/vibe.md) |

Copy `config/docker-compose.local.example.yml` to
`config/docker-compose.local.yml`, add only
the project mounts the sandbox should see, provide the required host-path and
identity variables, then run:

```bash
docker compose up -d --build
```

## Documentation

- [Setup and host integration](docs/setup.md)
- [AWS credential proxy](docs/aws.md)
- [Claude Code](docs/claude-code.md)
- [Codex](docs/codex.md)
- [pi](docs/pi.md)
- [Mistral Vibe](docs/vibe.md)
- [Session lifecycle](docs/lifecycle.md)
- [Development](docs/development.md)
- [Security model](docs/security.md)

## License

See [LICENSE](LICENSE).
