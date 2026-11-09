#!/bin/bash
# Package-manager download caches must not ship in the image: every npm install
# removes /root/.npm in its own RUN, and every uv install runs without a cache.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_instructions=$(awk '
  /^RUN / { collecting = 1; instruction = "" }
  collecting {
    line = $0; sub(/^[[:space:]]+/, "", line)
    if (line ~ /^#/) next
    continued = sub(/\\$/, "", line)
    instruction = instruction " " line
    if (!continued) { print instruction; collecting = 0 }
  }
' "$ROOT/Dockerfile")

npm_installs=$(grep -c 'npm install -g' <<<"$run_instructions" || true)
((npm_installs > 0)) || { echo 'found no npm install in the Dockerfile' >&2; exit 1; }
while IFS= read -r instruction; do
  [[ "$instruction" == *'rm -rf /root/.npm'* ]] || {
    echo "npm install leaves its cache in the layer:$instruction" >&2; exit 1; }
done < <(grep 'npm install -g' <<<"$run_instructions")

uv_installs=$(grep -c 'uv tool install' <<<"$run_instructions" || true)
((uv_installs > 0)) || { echo 'found no uv tool install in the Dockerfile' >&2; exit 1; }
while IFS= read -r instruction; do
  cached_installs=${instruction//uv tool install --no-cache /}
  [[ "$cached_installs" != *'uv tool install '* ]] || {
    echo "uv tool install leaves its cache in the layer:$instruction" >&2; exit 1; }
done < <(grep 'uv tool install' <<<"$run_instructions")

echo 'image install caches: ok'
