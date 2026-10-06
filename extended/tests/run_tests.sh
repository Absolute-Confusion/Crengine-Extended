#!/bin/sh
# Runs the crengine-extended test suites on a KOReader built with the patch (./kodev build)
# and with the plugin installed in its plugins/ folder.
#
# Usage:
#   ./run_tests.sh /path/to/koreader              # all suites
#   ./run_tests.sh /path/to/koreader slant cache  # only suites whose name contains a word
#   add --keep to keep the work folder (logs, test books, KOReader data) even if all pass
#
# Your KOReader settings, books and font caches are never used or changed: KOReader's data goes
# to a throwaway folder (KO_HOME), and only KOReader's bundled fonts and this folder's test
# fonts are installed (XDG_DATA_HOME/fonts; system fonts are off in KOReader's default settings).

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
KEEP=0
KO=""
FILTERS=""
for a in "$@"; do
    case "$a" in
        --keep) KEEP=1 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) if [ -z "$KO" ]; then KO="$a"; else FILTERS="$FILTERS $a"; fi ;;
    esac
done
if [ -z "$KO" ]; then
    echo "usage: $0 [--keep] /path/to/koreader [suite words...]" >&2
    exit 2
fi
EMU=$(ls -d "$KO"/koreader-emulator-*/koreader 2> /dev/null | head -1)
if [ -z "$EMU" ] || [ ! -e "$EMU/luajit" ]; then
    echo "error: no built emulator in $KO (run ./kodev build there first)" >&2
    exit 2
fi
if [ ! -f "$KO/plugins/advancedtypography.koplugin/main.lua" ]; then
    echo "error: the plugin isn't installed in $KO/plugins/advancedtypography.koplugin" >&2
    exit 2
fi
if ! diff -rq "$HERE/../plugin/advancedtypography.koplugin" "$KO/plugins/advancedtypography.koplugin" > /dev/null 2>&1; then
    echo "note: the installed plugin differs from this repository's copy (extended/plugin): testing the installed one"
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/advancedtypography-tests.XXXXXX") || exit 2
mkdir -p "$WORK/home" "$WORK/xdg/fonts" "$WORK/books" "$WORK/logs"
cp "$HERE"/fonts/*.ttf "$WORK/xdg/fonts/"
export KO_HOME="$WORK/home" XDG_DATA_HOME="$WORK/xdg" AT_TESTS="$HERE" AT_WORK="$WORK"
cd "$EMU" || exit 2

echo "KOReader: $EMU"
echo "Work folder: $WORK"
echo
PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=""
START=$(date +%s)
for suite in "$HERE"/suites/*.lua; do
    name=$(basename "$suite" .lua)
    if [ -n "$FILTERS" ]; then
        match=0
        for w in $FILTERS; do
            case "$name" in *"$w"*) match=1 ;; esac
        done
        [ "$match" = 1 ] || continue
    fi
    log="$WORK/logs/$name.log"
    t0=$(date +%s)
    timeout 3600 ./luajit "$suite" > "$log" 2>&1
    rc=$?
    secs=$(( $(date +%s) - t0 ))
    summary=$(grep -E '^[0-9]+ failure\(s\)$' "$log" | tail -1)
    skip=$(grep -E '^SKIP' "$log" | head -1)
    if [ "$rc" = 0 ] && [ "$summary" = "0 failure(s)" ] && [ -n "$skip" ]; then
        SKIPPED=$((SKIPPED + 1))
        printf 'SKIP  %-28s %4ss  (%s)\n' "$name" "$secs" "$(echo "$skip" | sed 's/^SKIP *//')"
    elif [ "$rc" = 0 ] && [ "$summary" = "0 failure(s)" ]; then
        PASSED=$((PASSED + 1))
        printf 'PASS  %-28s %4ss\n' "$name" "$secs"
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES="$FAILED_NAMES $name"
        printf 'FAIL  %-28s %4ss  (exit %s, %s)\n' "$name" "$secs" "$rc" "${summary:-no summary: crashed?}"
        grep -E '^FAIL|rror|traceback' "$log" | grep -v 'failed to register' | head -15 | sed 's/^/        /'
    fi
done
echo
echo "$PASSED passed, $FAILED failed, $SKIPPED skipped, in $(( $(date +%s) - START ))s"
if [ "$FAILED" -gt 0 ]; then
    echo "Failed:$FAILED_NAMES"
    echo "Full logs: $WORK/logs/"
    exit 1
fi
if [ "$KEEP" = 1 ]; then
    echo "Work folder kept: $WORK"
else
    rm -rf "$WORK"
fi
exit 0
