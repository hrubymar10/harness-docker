# Mistral Vibe

Mistral Vibe is installed as the `mistral-vibe` Python tool. Set the
`VIBE_VERSION` image build argument to pin a release; an empty value installs
the newest release that ships a wheel installable on the image's musl-based
Alpine base. Releases published only as glibc wheels or source are skipped,
because building Vibe from source needs a Rust toolchain the image does not
include; a pinned version must therefore have a compatible wheel. The image
supplies `vibe-session` and `vibe-notifier` integration commands. The image
sets `VIBE_ENABLE_SYSTEM_TRUST_STORE=true`, so Vibe verifies TLS against the
image's OS trust store, which every rebuild upgrades, instead of the certifi
bundle pinned in its own environment.

Vibe state defaults to `~/.vibe`. Authenticate with Vibe's `/login` flow or
provide `MISTRAL_API_KEY`. Treat the mounted state and provider key as readable
by all processes in the sandbox.

A program that runs Vibe once per turn can configure it for that session through
the environment (`VIBE_HOME`, `VIBE_ACTIVE_MODEL`, `VIBE_MCP_SERVERS`,
`VIBE_SESSION_LOGGING__SAVE_DIR`, and the variable a bearer key is read from) by
listing the names in `HARNESS_DOCKER_FORWARD_ENV`; see
[Session lifecycle](lifecycle.md). It should also set `VIBE_LAUNCH_FLAGS=`
(empty) when it passes its own flags, which replaces the built-in `--yolo`.

Run `vibe-docker`; arguments are forwarded after `--yolo`, or after
`VIBE_LAUNCH_FLAGS` when that override is set. Integrations that accept a CLI
executable can use the absolute path to
`vibe-docker-vscode-wrapper`. The launcher exports `VIBE_SESSION_ID` and uses
the mounted `VIBE_HOME`.
