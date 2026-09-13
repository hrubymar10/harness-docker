# Known security issues and trade-offs

`harness-docker` improves isolation from accidental coding-agent actions. It does not make arbitrary code execution safe and is not designed to contain a deliberately adversarial process.

## 1. Local volume driver bind escape

**Status:** Open upstream limitation

**Severity:** Medium

**Requires:** Raw Docker API requests rather than the normal wrapped CLI

The socket proxy validates ordinary binds and `Type: bind` mounts, but it does not inspect a local volume driver's `device` and `o=bind` options. A caller can create a local-driver volume backed by an arbitrary host path, then attach that volume to a container.

**Impact:** Read/write access to a host path outside the derived allowlist.

**Mitigations:** The Docker CLI wrapper blocks `docker run` and `docker cp`; the filter proxy rejects dangerous container configuration; and exploiting this remaining gap requires deliberately crafted raw API requests. Do not expose the Docker API when hostile-code containment is required.

## 2. Feature-branch and force pushes are allowed

**Status:** By design

**Severity:** Low

The Git wrapper blocks pushes only to configured protected branches (`main` and `master` by default) and blocks tag publication. It allows normal and force pushes to other branches.

**Impact:** A harness can rewrite any non-protected remote branch its credentials may update.

**Rationale:** Feature-branch pushes are part of the intended daily workflow. Enforce authoritative branch policy on the Git server.

## 3. The Git wrapper has an explicit bypass

**Status:** Accepted trade-off

**Severity:** Low

The real executable remains available as `/usr/libexec/git-real/git`. Calling it directly bypasses the protected-branch and tag checks. Passwordless sudo would also defeat a permissions-only restriction on that binary.

**Impact:** A caller that deliberately selects the bypass can push any ref permitted by its remote credentials.

**Rationale:** The wrapper catches accidental commands caused by bad prompts; it is not a security boundary. Server-side protected branches and tag rules are the real fix.

## 4. Passwordless sudo is available inside the container

**Status:** By design

**Severity:** Low, container-scoped

The development user has passwordless sudo and therefore root access inside the container.

The container is not privileged, and the filter rejects host namespace modes, excess capabilities, devices, unsafe security options, and unapproved bind mounts. Root still expands what a process can inspect or modify within the container and mounted paths.

## 5. Tokens and generated credentials are readable

**Status:** Accepted trade-off

**Severity:** Low to medium

API and Git-host tokens can appear in the process environment, generated credential helpers, or CLI configuration. Any process already running in the container may be able to read them and exfiltrate them through unrestricted network access.

Use narrowly scoped credentials, keep them out of mounted project trees, and revoke them if the container executes untrusted code.

## 6. Harness state is mounted read-write

**Status:** Required for operation

**Severity:** Medium

The following host directories are mounted read-write when configured:

- `CLAUDE_CONFIG_DIR`, normally `~/.claude`
- `CODEX_HOME`, normally `~/.codex`
- `PI_CODING_AGENT_DIR`, normally `~/.pi/agent`, plus optional `PI_PACKAGE_DIR`
- `VIBE_HOME`, normally `~/.vibe`
- OpenCode configuration, normally `~/.config/opencode`, and auth/data, normally `~/.local/share/opencode`

They may contain authentication, configuration, sessions, history, prompts, skills, extensions, packages, themes, trusted-folder state, or model definitions.

**Impact:** A compromised process can read, corrupt, or persist changes in every mounted harness state directory.

## 7. Network egress is unrestricted

**Status:** By design

**Severity:** Low to medium

Package installation, Git hosts, model providers, and normal development tools require outbound connectivity. A compromised process can therefore contact arbitrary remote services and exfiltrate readable data.

Use a separate network policy or an offline environment when egress control is required.

## 8. The allowed Docker API remains broad

**Status:** Accepted trade-off

**Severity:** Medium

The socket proxy permits a useful subset of container, image, network, volume, exec, event, and BuildKit APIs. The filter proxy inspects container-create bodies and rejects non-canonical paths, but an intentional raw client can still create and delete ordinary resources.

The proxy rejects privileged mode, host PID/network/user namespaces, devices, dangerous capabilities, unsafe security options, unauthorized binds, and decoded paths that differ from their canonical form. These checks reduce impact without pretending the API is narrow.

An image-tag allowlist was deliberately rejected because it would break legitimate generic BuildKit workflows. The CLI wrapper instead warns when a build targets a sandbox image name.

## 9. Inspect and logs expose information

**Status:** Accepted trade-off

**Severity:** Low to medium

The wrapped Docker CLI permits useful debugging commands including `docker inspect` and `docker logs`.

**Impact:** Inspection can reveal environment variables and metadata; logs can reveal application output for visible containers.

**Rationale:** Removing these commands would interfere with common debugging workflows.

## 10. Harness-level bypass flags reduce internal guardrails

**Status:** By design

**Severity:** Medium

The Claude and Codex launchers use their non-interactive permission-bypass flags, the Vibe launcher uses its autonomous mode flag, and OpenCode uses automatic approval. The outer container is intended to be the primary accident boundary, but these flags reduce defense in depth within the harness itself.

Do not rely on an individual harness's approval UI to protect mounted paths.

## 11. Extensions and instruction sources are trusted

**Status:** By design

**Severity:** Medium

Installed pi or Vibe packages and OpenCode plugins may execute code. Skills, prompts, repository instructions, hooks, and model/provider configuration for any harness can change agent behavior. Claude hooks can also invoke host-reachable notification services.

Review third-party packages and instruction files, and treat them as trusted code or trusted input.

## Security layers

```text
harness process
  └─ docker wrapper        normal CLI allowlist and warnings
      └─ filter proxy      canonical paths and container-body policy
          └─ socket proxy  method, route, and direct-bind filtering
              └─ Docker daemon

harness process
  └─ Git wrapper           protected branches and tag rejection
      └─ git-real          explicit best-effort bypass
```

Each Docker layer provides defense in depth. The Git wrapper remains an accident guard only.

## Practical advice

- Mount only project roots you need.
- Mask sensitive files and directories with `x-excludes`.
- Use narrowly scoped API and Git credentials.
- Enforce branch and tag protection on the server.
- Review installed packages, extensions, hooks, prompts, skills, and repository instructions.
- Do not use this sandbox as the sole boundary for hostile code.
