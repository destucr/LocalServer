#!/bin/zsh
# One-command release. Usage: ./release.sh 1.1.0
set -euo pipefail
cd "$(dirname "$0")"
V="${1:?usage: ./release.sh <version, e.g. 1.1.0>}"

[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean — commit or stash first."; exit 1; }
git rev-parse "v$V" >/dev/null 2>&1 && { echo "Tag v$V already exists."; exit 1; }

echo "$V" > VERSION
git commit -qam "Release $V"
./build.sh release
git tag "v$V"
git push -q origin HEAD "v$V"
gh release create "v$V" "build/LocalServer-$V.zip" --title "LocalServer $V" --generate-notes
echo "Released v$V"
