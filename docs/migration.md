# Migration from standalone stacks

`harness-docker` detects running standalone `claude-docker`, `codex-docker`,
`pi-docker`, and `vibe-docker` Compose projects. On first start it prints an
informational, one-shot notice with relevant cleanup commands. It never stops or
removes legacy resources itself.

Before switching, stop active work and back up local configuration. Replace the
old repository's `bin/` entry on `PATH` with this repository's `bin/`; launcher
names remain unchanged. Repoint editor wrapper paths to the same wrapper
filenames under this checkout.

Preserve the existing harness state directories and authentication described in
[Setup](setup.md). Convert local Compose overrides to the shared `harness`
service and copy any notifier script or environment overrides into the ignored
shared configuration. Start the shared controller, verify its status and one
harness command, then use the notice's explicit Compose commands to retire old
stacks when ready.
