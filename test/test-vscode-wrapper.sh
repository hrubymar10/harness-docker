#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); POINTER="$ROOT/config/.current-generation"; POINTER_BACKUP=""
restore() { if [[ -n "$POINTER_BACKUP" ]]; then cp "$POINTER_BACKUP" "$POINTER"; else rm -f "$POINTER"; fi; rm -rf "$TMP"; }
trap restore EXIT
if [[ -f "$POINTER" ]]; then POINTER_BACKUP="$TMP/current-generation.bak"; cp "$POINTER" "$POINTER_BACKUP"; fi
mkdir -p "$TMP/bin"
for harness in codex pi vibe; do
  cp "$ROOT/bin/$harness-docker-vscode-wrapper" "$TMP/bin/"
  cat > "$TMP/bin/$harness-docker" <<'EOF'
#!/bin/bash
printf '%s:' "$(basename "$0")" >> "$LOG"; printf '%s|' "$@" >> "$LOG"; printf '\n' >> "$LOG"
EOF
  chmod +x "$TMP/bin/$harness-docker" "$TMP/bin/$harness-docker-vscode-wrapper"
  LOG="$TMP/log" "$TMP/bin/$harness-docker-vscode-wrapper" --one 'two words'
  grep -Fq "$harness-docker:--one|two words|" "$TMP/log"
done

mkdir -p "$TMP/work"; cat > "$TMP/bin/docker" <<'EOF'
#!/bin/bash
printf '%q ' "$@" >> "$LOG"; printf '\n' >> "$LOG"
case "$1" in info) ;; ps) echo cid ;; inspect) [[ "$*" == *State.Status* ]] && echo running || echo "$MOUNT" ;; exec) [[ "$*" == *'echo "$#"'* ]] && echo 0 || echo stream ;; esac
EOF
chmod +x "$TMP/bin/docker"
printf 'manual\n' > "$POINTER"
(cd "$TMP/work"; PATH="$TMP/bin:$PATH" LOG="$TMP/log2" MOUNT="$TMP" HARNESS_DOCKER_SKIP_UPDATE_CHECK=1 "$ROOT/bin/claude-docker-vscode-wrapper" /host/claude --output-format stream-json > "$TMP/out")
grep -Eq 'exec -i .*CLAUDE_SESSION_ID=.* claude-session --output-format stream-json' "$TMP/log2"
if grep -q 'exec -it' "$TMP/log2"; then exit 1; fi
if grep -q '/host/claude' "$TMP/log2"; then exit 1; fi
grep -q stream "$TMP/out"
echo 'vscode wrappers: ok'
