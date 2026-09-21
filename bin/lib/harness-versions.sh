# shellcheck shell=bash

_HARNESS_VERSION_NAMES=(claude codex pi vibe opencode)
_HARNESS_VERSION_MANIFEST=/opt/harness-docker/harness-versions

harness_image_tag() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9_.-]/-/g; s/^[.-]/v&/'
}

generation_harness_image() {
  local generation="$1" container version tag
  container=$(generation_agent_container_id "$generation") || return 1
  [[ -n "$container" ]] || return 1
  version=$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$container" 2>/dev/null) || return 1
  [[ -n "$version" ]] || return 1
  tag=$(harness_image_tag "$version")
  printf 'harness-docker:%s' "$tag"
}

_manifest_version() {
  local manifest="$1" name="$2"
  awk -F= -v name="$name" '$1 == name { print substr($0, length(name) + 2); exit }' <<< "$manifest"
}

read_harness_version_manifest() {
  local image="$1" manifest name version
  manifest=$(docker run --rm --entrypoint cat "$image" "$_HARNESS_VERSION_MANIFEST" 2>/dev/null) || return 1
  for name in "${_HARNESS_VERSION_NAMES[@]}"; do
    version=$(_manifest_version "$manifest" "$name")
    [[ -n "$version" ]] || return 1
  done
  printf '%s\n' "$manifest"
}

print_harness_version_summary() {
  local new_manifest="$1" old_manifest="${2:-}" name new_version old_version
  for name in "${_HARNESS_VERSION_NAMES[@]}"; do
    new_version=$(_manifest_version "$new_manifest" "$name")
    old_version=$(_manifest_version "$old_manifest" "$name")
    if [[ -z "$new_version" || "$new_version" == unknown ]] \
      || [[ -n "$old_manifest" && "$old_version" == unknown ]]; then
      printf '* %s (version unavailable)\n' "$name"
    elif [[ -z "$old_manifest" ]]; then
      printf '* %s v%s\n' "$name" "$new_version"
    elif [[ "$old_version" == "$new_version" ]]; then
      printf '* %s v%s (Already up-to-date)\n' "$name" "$new_version"
    else
      printf '* %s v%s -> v%s\n' "$name" "$old_version" "$new_version"
    fi
  done
}
