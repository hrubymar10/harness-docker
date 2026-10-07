#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/harness-versions.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/manifests"

cat > "$TEST_ROOT/bin/docker" <<'MOCK'
#!/bin/bash
set -euo pipefail
if [[ "$1" == run && "$2" == --rm && "$3" == --entrypoint && "$4" == cat \
  && "$6" == /opt/harness-docker/harness-versions ]]; then
  image=${5#harness-docker:}
  cat "$MOCK_MANIFESTS/$image"
elif [[ "$1" == inspect && "$2" == --format ]]; then
  printf '%s\n' "$MOCK_IMAGE_VERSION"
else
  exit 2
fi
MOCK
chmod +x "$TEST_ROOT/bin/docker"

export PATH="$TEST_ROOT/bin:$PATH"
export MOCK_MANIFESTS="$TEST_ROOT/manifests"

generation_agent_container_id() { printf 'container-old'; }
# shellcheck disable=SC1091
source "$ROOT/bin/lib/harness-versions.sh"

assert_eq() {
  [[ "$1" == "$2" ]] || { printf "assertion failed:\n--- got ---\n%s\n--- want ---\n%s\n" "$1" "$2" >&2; exit 1; }
}

old_manifest=$'claude=2.1.0\ncodex=1.2.3\npi=0.8.0\nvibe=unknown\nopencode=1.0.0'
new_manifest=$'claude=2.1.0\ncodex=2.3.4\npi=0.9.0\nvibe=1.2.0\nopencode=1.0.0'
printf '%s\n' "$old_manifest" > "$MOCK_MANIFESTS/old"
printf '%s\n' "$new_manifest" > "$MOCK_MANIFESTS/new"

assert_eq "$(harness_image_tag '/bad version')" 'v-bad-version'
export MOCK_IMAGE_VERSION='/bad version'
assert_eq "$(generation_harness_image old-generation)" 'harness-docker:v-bad-version'
assert_eq "$(read_harness_version_manifest harness-docker:new)" "$new_manifest"
if read_harness_version_manifest harness-docker:missing >/dev/null; then
  echo 'missing manifest unexpectedly succeeded' >&2
  exit 1
fi

expected_plain=$'* claude v2.1.0\n* codex v2.3.4\n* pi v0.9.0\n* vibe v1.2.0\n* opencode v1.0.0'
assert_eq "$(print_harness_version_summary "$new_manifest")" "$expected_plain"

expected_diff=$'* claude v2.1.0 (Already up-to-date)\n* codex v1.2.3 -> v2.3.4\n* pi v0.8.0 -> v0.9.0\n* vibe (version unavailable)\n* opencode v1.0.0 (Already up-to-date)'
assert_eq "$(print_harness_version_summary "$new_manifest" "$old_manifest")" "$expected_diff"

incompatible_new=$'claude=2.1.0\ncodex=2.3.4\npi=0.9.0\nvibe=1.2.0\nvibe.latest=1.3.0\nopencode=1.0.0'
assert_eq "$(print_harness_version_summary "$incompatible_new" | grep vibe)" '* vibe v1.2.0 (latest v1.3.0 is not compatible)'
same_old=$'claude=2.1.0\ncodex=2.3.4\npi=0.9.0\nvibe=1.2.0\nopencode=1.0.0'
assert_eq "$(print_harness_version_summary "$incompatible_new" "$same_old" | grep vibe)" '* vibe v1.2.0 (latest v1.3.0 is not compatible)'
older_old=$'claude=2.1.0\ncodex=2.3.4\npi=0.9.0\nvibe=1.1.0\nopencode=1.0.0'
assert_eq "$(print_harness_version_summary "$incompatible_new" "$older_old" | grep vibe)" '* vibe v1.1.0 -> v1.2.0 (latest v1.3.0 is not compatible)'

empty_new=''
expected_unavailable=$'* claude (version unavailable)\n* codex (version unavailable)\n* pi (version unavailable)\n* vibe (version unavailable)\n* opencode (version unavailable)'
assert_eq "$(print_harness_version_summary "$empty_new")" "$expected_unavailable"

echo 'harness version summary: ok'
