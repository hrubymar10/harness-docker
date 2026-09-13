# Security model

`harness-docker` is designed to reduce accidental damage from coding-agent
commands. It is a safety net for bad prompts, not a boundary against hostile
code. Do not expose credentials or host paths that an untrusted process must not
read.

The initial defense-in-depth helpers are:

- `docker-filter-proxy`, which accepts only canonical API paths and validates
  container-create requests against allowed bind sources and safe namespace,
  capability, privilege, and device settings;
- the in-container Docker wrapper, which narrows normal CLI use and blocks
  high-risk convenience commands while retaining common Compose, build, and
  debugging workflows; and
- the Git configuration and wrappers, which provide an explicit place for
  push-policy enforcement. The guarded Git command rejects tag publication and
  pushes to configured protected branches, while its explicitly named real
  binary remains available for deliberate bypass.

The entrypoint may copy mounted Git credentials, CLI tokens, signing keys, and
other host configuration into the sandbox user's home. Those values are
available to sandbox processes. Mount only the state needed for the intended
workflow and rely on provider-side permissions and server-side branch protection
for authoritative enforcement.

These controls reduce mistakes without pretending that arbitrary code is safe.
Server-side repository protection remains authoritative, and any mounted state,
credentials, or environment variables are visible to processes that can read
them.
