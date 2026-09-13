#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/git" <<'EOF'
#!/bin/bash
case "$1 $2" in
  'symbolic-ref HEAD') echo "${STUB_HEAD_REF:-refs/heads/feature}" ;;
  'remote get-url') [[ "${STUB_REMOTE_MISSING:-0}" != 1 ]] && printf '%s\n' "${STUB_REMOTE_URL:-git@github.com:acme/example.git}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/git"; export GIT_REAL_OVERRIDE="$TMP/git"
# shellcheck disable=SC1091
source "$ROOT/scripts/git-wrapper.sh"
block() { should_block_push "$@" || { echo "should block: $*" >&2; exit 1; }; }
allow() { ! should_block_push "$@" || { echo "should allow: $*" >&2; exit 1; }; }
tag_block() { should_block_tag_push "$@" || { echo "should block tag: $*" >&2; exit 1; }; }
tag_allow() { ! should_block_tag_push "$@" || { echo "should allow tag: $*" >&2; exit 1; }; }
block origin HEAD:refs/heads/main; block origin +HEAD:refs/heads/master; block origin main; block origin :main
block -o value origin main; block --push-option value origin main; block --receive-pack value origin main
block --repo value origin main; block --exec /bin/x origin main
block --push-option=value origin main; block --repo=value origin main
block --force-with-lease=feature origin main; block --signed=true origin main
block -- origin main; allow origin feature; allow origin main:feature; allow origin +feature
STUB_HEAD_REF=refs/heads/main block origin; STUB_HEAD_REF=refs/heads/feature allow origin
block origin feature HEAD:main; allow origin feature bug
GIT_PROTECTED_BRANCHES='develop release' block origin develop
GIT_PROTECTED_BRANCHES='develop release' allow origin main
GIT_PROTECTED_BRANCHES=refs/heads/develop block origin develop
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets STUB_REMOTE_URL=git@github.com:acme/widgets.git allow origin main
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets STUB_REMOTE_URL=https://GITHUB.COM/acme/widgets.git allow upstream main
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets allow https://github.com/acme/widgets.git main
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets STUB_REMOTE_URL=git@github.com:acme/widgets2.git block origin main
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets STUB_REMOTE_URL=git@evil.com:acme/widgets.git block origin main
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets STUB_REMOTE_MISSING=1 block origin main
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets STUB_REMOTE_URL=$'git@github.com:acme/other.git\nhttps://github.com/acme/widgets.git' block dual main
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets STUB_REMOTE_URL=$'https://github.com/acme/widgets.git\ngit@github.com:acme/other.git' block dual main
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets STUB_REMOTE_URL=$'git@github.com:acme/widgets.git\nhttps://GITHUB.COM/acme/widgets.git' allow dual main
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets block $'https://github.com/acme/widgets.git\nhttps://github.com/acme/widgets.git' main
GIT_PROTECTED_BRANCH_EXEMPT_REPOS='' block origin main
for args in 'origin --tags' '--follow-tags origin' '--mirror origin' 'origin refs/tags/v1.0' 'origin +refs/tags/v1.0' 'origin HEAD:refs/tags/v1.0' 'origin :refs/tags/v1.0' 'origin tag v1.0'; do read -r -a a <<< "$args"; tag_block "${a[@]}"; done
tag_block origin feature refs/tags/v1.0
GIT_PROTECTED_BRANCH_EXEMPT_REPOS=github.com/acme/widgets STUB_REMOTE_URL=git@github.com:acme/widgets.git tag_block origin refs/tags/v2.0
tag_allow origin feature; tag_allow origin HEAD:refs/heads/feature; tag_allow
echo 'git wrapper: ok'
