#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
#
# The repo-specific checks. Both workflows call this if it is executable, so
# anything here runs on every commit on every branch and again in front of a
# release.
#
# Three things the generic deck guards cannot know about:
#
#   1  the fuzz sweep (tools/fuzz.j) - the deck promises that damage a reader
#      can work around is not an error, and that promise is only as good as
#      what has been thrown at it
#   2  every exported function is reached by the test overlay - jvc requires a
#      co-located _test.j per module, which check-overlays.sh enforces, but an
#      overlay can exist and still not touch a new export
#   3  src/ holds nothing but .j files - it is the subtree jvc vendors, and a
#      hidden 0600 `.jfmt-*.tmp` from a crashed `jennifer fmt -w` is invisible
#      to `fmt -l`, `lint` and `git status`. pack.sh refuses one at release
#      time; this catches it on the commit that introduced it.
#
# Usage: tools/check-extra.sh
set -euo pipefail
cd "$(dirname "$0")/.."

JENNIFER="${JENNIFER:-jennifer}"

# --- 3: src/ purity, first because it is instant ---------------------------
stray="$(find src -type f ! -name '*.j' | sort)"
if [[ -n "$stray" ]]; then
    echo "error: src/ holds files that are not Jennifer source:" >&2
    printf '  %s\n' $stray >&2
    echo "" >&2
    echo "src/ is the subtree jvc vendors into a consumer's tree. A" >&2
    echo "\`.jfmt-*.tmp\` is the leftover of a crashed \`jennifer fmt -w\`;" >&2
    echo "remove it and re-run the format." >&2
    exit 1
fi
echo "src/ holds only Jennifer source"

# --- 2: every export is reached by a test ----------------------------------
python3 - <<'PYCOVER'
import re, glob, sys

sources = [f for f in sorted(glob.glob('src/**/*.j', recursive=True))
           if not f.endswith('_test.j')]
exports = {}
for f in sources:
    for m in re.finditer(r'^export func ([A-Za-z][A-Za-z0-9]*)\(', open(f, encoding='utf-8').read(), re.M):
        exports[m.group(1)] = f

overlay = "".join(open(f, encoding='utf-8').read()
                  for f in sorted(glob.glob('src/**/*_test.j', recursive=True)))

missing = sorted(n for n in exports if not re.search(r'\b' + n + r'\s*\(', overlay))
if missing:
    print("", file=sys.stderr)
    for n in missing:
        print(f"  {exports[n]}: {n}() is exported but never called from an overlay",
              file=sys.stderr)
    print(f"\n{len(missing)} of {len(exports)} exported function(s) are untested.",
          file=sys.stderr)
    sys.exit(1)
print(f"all {len(exports)} exported functions are called from the test overlay")
PYCOVER

# --- 1: the fuzz sweep -----------------------------------------------------
# Seeded, so a failure here reproduces exactly. Roughly eight seconds.
$JENNIFER run tools/fuzz.j
