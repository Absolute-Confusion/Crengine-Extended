#!/bin/sh
# Regenerates patch/crengine-extended.patch (git format, records its base version) and
# patch/crengine-extended.diff (plain diff) from this branch's crengine commit: the commit
# whose subject starts with "Crengine-Extended for KOReader", against its parent (the base).
#
# Usage: ./make_patch.sh   (from a checkout of the extended branch, after porting or changing
# the crengine commit; then commit the regenerated files in the extended/ commit)

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/.."
COMMIT=$(git log -1 --format=%H --grep='^Crengine-Extended for KOReader' HEAD)
if [ -z "$COMMIT" ]; then
    echo "error: no commit with a subject starting with \"Crengine-Extended for KOReader\" on this branch" >&2
    exit 2
fi
BASE=$(git rev-parse "$COMMIT^")
mkdir -p "$HERE/patch"
git format-patch -1 --zero-commit --base="$BASE" --stdout "$COMMIT" > "$HERE/patch/crengine-extended.patch"
git diff "$BASE" "$COMMIT" > "$HERE/patch/crengine-extended.diff"
echo "crengine commit: $(git log -1 --format='%h %s' "$COMMIT")"
echo "base:            $(git log -1 --format='%h %cs %s' "$BASE")"
git diff --stat "$BASE" "$COMMIT" | tail -1
