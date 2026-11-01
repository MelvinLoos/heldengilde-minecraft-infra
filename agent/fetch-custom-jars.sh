#!/usr/bin/env bash
# Fetches the jars listed in a custom-jars lock file into DEST and verifies sha256 (ADR 0005).
# Usage: fetch-custom-jars.sh LOCK_JSON DEST [--allow-missing-premium]
# Premium jars (source "local:<file>") are read from $HG_PREMIUM_DIR.
set -euo pipefail

lock=${1:?lock file}
dest=${2:?destination dir}
allow_missing=${3:-}
premium_dir=${HG_PREMIUM_DIR:-}

mkdir -p "$dest"
status=0

while IFS=$'\t' read -r name source sha; do
  target="$dest/$name"
  if [ -f "$target" ] && [ "$(sha256sum "$target" | cut -d' ' -f1)" = "$sha" ]; then
    echo "ok       $name (cached)"
    continue
  fi
  case "$source" in
    local:*)
      src="$premium_dir/${source#local:}"
      if [ -z "$premium_dir" ] || [ ! -f "$src" ]; then
        if [ "$allow_missing" = "--allow-missing-premium" ]; then
          echo "skipped  $name (premium jar not available)"
          continue
        fi
        echo "MISSING  $name (expected at $src)" >&2
        status=1
        continue
      fi
      cp "$src" "$target.part"
      ;;
    *)
      curl -fsSL --retry 3 -o "$target.part" "$source"
      ;;
  esac
  actual=$(sha256sum "$target.part" | cut -d' ' -f1)
  if [ "$actual" != "$sha" ]; then
    echo "MISMATCH $name: expected $sha, got $actual" >&2
    rm -f "$target.part"
    status=1
    continue
  fi
  mv "$target.part" "$target"
  echo "fetched  $name"
done < <(jq -r '.jars[] | [.name, .source, .sha256] | @tsv' "$lock")

exit "$status"
