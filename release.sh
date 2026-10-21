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

# Update the Homebrew cask (destucr/homebrew-tap) with the new version + checksum
SHA="$(shasum -a 256 "build/LocalServer-$V.zip" | cut -d' ' -f1)"
CASK="Casks/localserver.rb"
CUR="$(gh api "repos/destucr/homebrew-tap/contents/$CASK")"
FILE_SHA="$(echo "$CUR" | jq -r .sha)"
NEW="$(echo "$CUR" | jq -r .content | base64 -d | sed -E "s/^(  version \").*(\")/\1$V\2/; s/^(  sha256 \").*(\")/\1$SHA\2/")"
gh api -X PUT "repos/destucr/homebrew-tap/contents/$CASK" -f message="localserver $V" \
  -f content="$(echo "$NEW" | base64)" -f sha="$FILE_SHA" -f branch=main --jq .commit.html_url
echo "Released v$V"
