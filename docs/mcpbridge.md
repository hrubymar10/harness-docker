# Host MCP gateway

`mcpbridge` is an optional host-side gateway for stdio MCP servers that cannot
run usefully inside the sandbox. It starts configured commands on the host and
publishes their tools and prompts through one Streamable HTTP endpoint. Tool and
prompt names are prefixed with the configured server name, for example
`xcode.build`.

Go 1.23 or newer is required to build the gateway. Copy and edit the example:

```bash
cp config/mcpbridge.jsonc.example config/mcpbridge.jsonc
```

The controller starts the gateway during `start` and `rebuild` when the config
contains at least one enabled server. It stops a running gateway when the file
is absent or every server is disabled. `stop` always stops it. The explicit
commands are useful after changing the config:

```bash
harness-docker-ctrl mcpbridge-stop
harness-docker-ctrl mcpbridge-start
```

Configuration is read only at process startup. A running gateway is not
restarted by a later `start`, so use the explicit stop/start pair to apply
changes. The PID is stored in `~/.harness-docker-mcpbridge.pid`.

Runtime output is appended to `config/logs/mcpbridge.log` instead of the
controller's terminal. If the allowlist blocks a request, inspect its direct
peer address there:

```bash
tail -f config/logs/mcpbridge.log
```

## Configuration

`config/mcpbridge.jsonc` accepts JSON with line and block comments, including
trailing commas. Unknown fields and invalid server entries stop startup rather
than silently reducing the published tool set.

- `listen` is an IP-literal host and port. It defaults to
  `127.0.0.1:9976`.
- `allow_list` is an array of source IPs or CIDRs. Bare addresses are treated
  as single-host prefixes. It defaults to `127.0.0.0/8` and `::1/128`.
- `servers` is an array of stdio MCP servers. Server names must be unique and
  contain only letters, digits, underscores, or hyphens.
- `servers[].command` is the host executable. `args` is its argument array.
- `servers[].env` overrides selected variables while retaining the host
  environment. `cwd` optionally sets the child working directory.
- `servers[].enabled` defaults to `true` when omitted.

Only stdio upstreams belong here. An MCP server that already speaks HTTP can be
registered directly with each sandboxed harness.

The gateway exposes tools and prompts. It intentionally does not federate MCP
resources because correct URI rewriting, templates, and subscriptions require
separate routing semantics.

For example, Xcode supplies a stdio MCP server through `xcrun`:

```jsonc
{
  "servers": [
    { "name": "xcode", "command": "xcrun", "args": ["mcpbridge"] }
  ]
}
```

## Register the gateway

Run the relevant sandbox launcher from the host, or otherwise update the
harness configuration mounted into the sandbox. The gateway does not modify
harness configuration automatically.

Claude Code:

```bash
claude-docker mcp add --scope user --transport http mcpbridge http://host.docker.internal:9976/mcp
```

Codex:

```bash
codex-docker mcp add mcpbridge --url http://host.docker.internal:9976/mcp
```

Mistral Vibe:

```bash
vibe-docker mcp add mcpbridge --transport streamable-http --url http://host.docker.internal:9976/mcp --no-login
```

OpenCode:

```bash
opencode-docker mcp add mcpbridge --url http://host.docker.internal:9976/mcp
```

Pi does not include MCP support. With a compatible MCP adapter installed, add
the gateway to the adapter config under the mounted Pi state directory (normally
`~/.pi/agent/mcp.json`), then launch it with `pi-docker`:

```json
{"mcpServers":{"mcpbridge":{"url":"http://host.docker.internal:9976/mcp"}}}
```

## Security

This feature deliberately lets sandboxed agents invoke programs running with
the host user's identity, filesystem access, environment, and credentials. Add
only upstream servers whose capabilities are appropriate for every configured
harness.

The default loopback bind and source allowlist follow the same host-reaching
posture as the SSH relay and beeper. Requests are checked against the direct
peer address; forwarded-address headers are not trusted. The endpoint has no
authentication, so keep the loopback bind unless a non-loopback interface and
a narrow allowlist are intentionally required.
