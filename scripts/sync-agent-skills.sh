#!/usr/bin/env bash
# Verify or refresh vendored agent skills listed in .agents/skill-sources.txt.
#
#   scripts/sync-agent-skills.sh           check: pinned upstream == .agents/skills, symlinks ok
#   scripts/sync-agent-skills.sh --apply   copy pinned upstream into .agents/skills, relink
#
# Only fetches files with git; never runs code from the fetched repositories.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
manifest="$root/.agents/skill-sources.txt"
mode="${1:-check}"
case "$mode" in check | --check) mode=check ;; --apply) mode=apply ;; *)
  echo "usage: $0 [--check|--apply]" >&2
  exit 2
  ;;
esac

if [[ $mode == apply ]] && ! git -C "$root" diff --quiet HEAD -- .agents/skills .claude/skills; then
  echo "refusing --apply: uncommitted changes under .agents/skills or .claude/skills" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() { # repo commit -> prints checkout dir
  local dir="$tmp/${1//\//_}@$2"
  if [[ ! -d $dir ]]; then
    git init -q "$dir"
    git -C "$dir" fetch -q --depth 1 "https://github.com/$1.git" "$2"
    git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
  fi
  echo "$dir"
}

drift=0
while read -r name repo commit path extra; do
  [[ -z ${name:-} || $name == \#* ]] && continue
  src="$(fetch "$repo" "$commit")"
  want="$tmp/want/$name"
  mkdir -p "$want"
  cp -R "$src/$path/." "$want/"
  [[ $extra != - ]] && cp "$src/$extra" "$want/"
  dest="$root/.agents/skills/$name"
  link="$root/.claude/skills/$name"

  if [[ $mode == apply ]]; then
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -R "$want/." "$dest/"
    rm -rf "$link"
    ln -s "../../.agents/skills/$name" "$link"
    echo "synced $name  ($repo@${commit:0:7})"
  else
    if ! diff -r "$want" "$dest" >/dev/null 2>&1; then
      echo "DRIFT   $name differs from $repo@${commit:0:7}"
      drift=1
    elif [[ "$(readlink "$link" 2>/dev/null)" != "../../.agents/skills/$name" ]]; then
      echo "LINK    .claude/skills/$name is not a symlink to ../../.agents/skills/$name"
      drift=1
    else
      echo "ok      $name"
    fi
  fi
done <"$manifest"

if [[ $mode == apply ]]; then
  echo "review with: git diff --stat -- .agents .claude"
fi
exit $drift
