#!/bin/sh
# Applies the crengine-extended patch to the crengine of a KOReader source tree.
#
# Usage:
#   ./apply.sh /path/to/koreader            # KOReader source tree (the one with ./kodev)
#   ./apply.sh --crengine /path/to/crengine # a crengine source tree directly
#   add --check to only report whether it would apply (nothing is changed)
#
# With git (crengine is a git checkout, as in KOReader), the patch is applied with a
# three-way merge: on a newer crengine, changes next to upstream edits merge
# automatically; only real overlaps are left as conflicts (marked in the files).
# Without git, it falls back to patch(1), which leaves *.rej files for what didn't apply.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
PATCH="$HERE/patch/crengine-extended.patch"
DIFF="$HERE/patch/crengine-extended.diff"
# The crengine version the patch is made against, as recorded in it
BASE=$(sed -n 's/^base-commit: //p' "$PATCH")
if [ -z "$BASE" ]; then
    echo "error: no base-commit line in $PATCH" >&2
    exit 2
fi

CHECK=0
CRENGINE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --crengine) shift; CRENGINE="${1:-}" ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) CRENGINE="$1/base/thirdparty/kpvcrlib/crengine" ;;
    esac
    shift
done
if [ -z "$CRENGINE" ] || [ ! -d "$CRENGINE/crengine/src" ]; then
    echo "error: crengine source tree not found${CRENGINE:+ at $CRENGINE}" >&2
    echo "usage: $0 [--check] /path/to/koreader   or   $0 [--check] --crengine /path/to/crengine" >&2
    exit 2
fi
cd "$CRENGINE" || exit 2
echo "crengine: $CRENGINE"

if git rev-parse --git-dir > /dev/null 2>&1; then
    # Already applied?
    if git apply --reverse --check --whitespace=nowarn "$PATCH" 2> /dev/null; then
        echo "The patch is already applied: nothing to do."
        exit 0
    fi
    # Never mix with other uncommitted changes in the files it touches
    if [ -n "$(git status --porcelain --untracked-files=no -- crengine)" ]; then
        echo "error: crengine has uncommitted changes; commit, stash or revert them first:" >&2
        git status --short --untracked-files=no -- crengine >&2
        exit 2
    fi
    HEAD=$(git rev-parse HEAD)
    if [ "$HEAD" = "$BASE" ]; then
        echo "crengine is at the patch's base version ($BASE): it applies exactly."
    else
        echo "crengine is at $HEAD, not at the patch's base ($BASE): three-way merge."
        if ! git cat-file -e "$BASE^{commit}" 2> /dev/null; then
            echo "warning: the base version isn't in this checkout's history (shallow clone?):" >&2
            echo "  three-way merging needs it; get it with:  git fetch origin $BASE  (or git fetch --unshallow)" >&2
        fi
    fi
    if [ "$CHECK" = 1 ]; then
        if git apply --check --whitespace=nowarn "$PATCH" 2> /dev/null; then
            echo "Check: it applies cleanly."
        else
            echo "Check: it doesn't apply cleanly by itself; a three-way merge (applying for real) may resolve it."
            git apply --check --whitespace=nowarn "$PATCH" 2>&1 | sed 's/^/  /' | head -20
        fi
        exit 0
    fi
    if git apply --3way --whitespace=nowarn "$PATCH"; then
        git reset -q -- crengine # keep the result as plain working tree changes
        echo
        echo "Done: the patch is applied."
    else
        echo
        echo "The patch is applied, except for the conflicts listed above. In each of those files," >&2
        echo "look for the <<<<<<< ======= >>>>>>> markers and keep both sides' intent, then rebuild." >&2
        git diff --name-only --diff-filter=U | sed 's/^/  conflict: /' >&2
        exit 1
    fi
else
    echo "Not a git checkout: applying with patch(1)."
    if [ "$CHECK" = 1 ]; then
        patch -p1 --forward --dry-run < "$DIFF"
        exit $?
    fi
    if patch -p1 --forward < "$DIFF"; then
        echo
        echo "Done: the patch is applied."
    else
        echo
        echo "Some changes didn't apply: see the *.rej files next to the files listed above." >&2
        exit 1
    fi
fi
echo "Next: rebuild KOReader (see README.md), and install the plugin from plugin/."
