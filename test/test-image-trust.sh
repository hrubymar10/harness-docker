#!/bin/bash
# Image trust-store freshness: package upgrades re-run on every rebuild and
# Vibe uses the OS store instead of its own certifi bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dockerfile="$ROOT/Dockerfile"

refresh_line=$(grep -n '^ARG HARNESS_REFRESH=' "$dockerfile" | cut -d: -f1 || true)
upgrade_line=$(grep -n '^RUN apk upgrade --no-cache$' "$dockerfile" | cut -d: -f1 || true)
first_cli_line=$(grep -n 'npm install -g "opencode-ai' "$dockerfile" | head -n 1 | cut -d: -f1 || true)
[[ $(grep -c '^ARG HARNESS_REFRESH=' "$dockerfile") == 1 ]] || {
  echo 'HARNESS_REFRESH must be declared exactly once' >&2; exit 1; }
[[ -n "$refresh_line" && -n "$upgrade_line" && -n "$first_cli_line" ]] || {
  echo 'missing HARNESS_REFRESH, apk upgrade, or the first CLI install' >&2; exit 1; }
((refresh_line < upgrade_line && upgrade_line < first_cli_line)) || {
  echo 'apk upgrade must run after HARNESS_REFRESH and before the CLI installs' >&2; exit 1; }
grep -q '^ENV VIBE_ENABLE_SYSTEM_TRUST_STORE=true$' "$dockerfile" || {
  echo 'Vibe must use the OS trust store' >&2; exit 1; }
echo 'image trust store: ok'
