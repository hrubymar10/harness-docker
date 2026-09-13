# Migration from standalone stacks

`harness-docker` replaces four separate images and Compose stacks with one image
and controller. The launchers remain `claude-docker`, `codex-docker`,
`pi-docker`, and `vibe-docker`; only their containing repository changes.

## 1. Stop and back up

Finish active harness sessions, stop the legacy stacks, and back up their ignored
environment, Compose override, notifier, and signing-key files. Do not remove
containers or images until the shared stack is verified.

## 2. Keep authentication and state

No re-authentication is normally needed. The shared stack uses the same host
state: `~/.claude` (or `CLAUDE_CONFIG_DIR`), `~/.codex`, `~/.pi/agent`, and
`~/.vibe`. Preserve explicit overrides. A harness never used before receives an
empty state directory and can be adopted later.

## 3. Repoint PATH

Replace the old repository's `bin/` entry in the shell profile:

```bash
export PATH="/path/to/harness-docker/bin:$PATH"
```

Open a new shell or source the profile. Launcher names do not change.

## 4. Repoint editor integrations

Update absolute VS Code paths to the same wrapper filenames under this
repository. Claude still uses `claudeCode.claudeProcessWrapper` with terminal
mode disabled; Codex still uses `chatgpt.cliExecutable`. JetBrains integration
is not currently supported.

## 5. Preserve harness configuration

Keep `CLAUDE_CONFIG_DIR="$HOME/.claude"` in the host shell. Codex, pi, and Vibe
default to `~/.codex`, `~/.pi/agent`, and `~/.vibe`; retain any explicit
overrides in the shell or copy them into `config/.env`.

## 6. Convert mounts and integrations

Rename a legacy local Compose service key (`claude`, `codex`, `pi`, or `vibe`)
to `harness` and save it as `config/docker-compose.local.yml`. Review all mounts
and exclusions rather than merging four files blindly. Copy one legacy notifier
to `config/harness-notifier`, make it executable, and transfer required GPG,
AWS-proxy, provider-key, and environment settings to the shared locations
described by the topic guides.

| Legacy item | Shared equivalent |
| --- | --- |
| `<harness>-docker-ctrl start/status/rebuild/stop` | `harness-docker-ctrl <command>` |
| `<harness>-docker` | unchanged launcher name |
| harness-specific Compose service | `harness` |
| harness-specific notifier | `config/harness-notifier` |
| harness-specific image/stack | one generation-aware shared image/stack |

## 7. Start and verify

```bash
harness-docker-ctrl start
harness-docker-ctrl status
claude-docker --version
```

Use another installed harness for the final command if appropriate. Status must
show a current generation before old resources are retired.

## 8. Retire old stacks

On first start, the controller detects running legacy projects and prints the
relevant cleanup commands once. It never executes them. From each old checkout,
run the appropriate explicit command when ready:

```bash
docker compose -p claude-docker down --rmi local
docker compose -p codex-docker down --rmi local
docker compose -p pi-docker down --rmi local
docker compose -p vibe-docker down --rmi local
```

Removing all four legacy local images reclaims roughly 8.5 GB. The one-shot
notice is informational and may be cleared without deleting anything.
