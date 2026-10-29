#!/usr/bin/env bash
#
# mayhem/test.sh — RUN upstream's GoogleTest UnitTest binary plus the ReaderTest (decodes test/samples) and
# WriterTest blackbox suites (all built by mayhem/build.sh) and report CTRF. UnitTest counts come from
# gtest's own summary lines, so a neutered binary (no output) cannot pass.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

runner=build/tests/test/unit/UnitTest
reader=build/tests/test/blackbox/ReaderTest
writer=build/tests/test/blackbox/WriterTest
for bin in "$runner" "$reader" "$writer"; do
  if [ ! -x "$bin" ]; then
    echo "test.sh: $bin missing — mayhem/build.sh should have built it" >&2
    emit_ctrf cmake-gtest 0 1 0
    exit 1
  fi
done

out=$(cd build/tests/test/unit && ./UnitTest 2>&1); rc=$?
printf '%s\n' "$out" | tail -n 30

total=$(printf '%s\n' "$out" | sed -n 's/^\[==========\] \([0-9][0-9]*\) tests\? from .* ran\..*/\1/p' | tail -n1)
passed=$(printf '%s\n' "$out" | sed -n 's/^\[  PASSED  \] \([0-9][0-9]*\) tests\?\./\1/p' | tail -n1)
failed=$(printf '%s\n' "$out" | sed -n 's/^\[  FAILED  \] \([0-9][0-9]*\) tests\?, listed below:/\1/p' | tail -n1)
skipped=$(printf '%s\n' "$out" | sed -n 's/^\[  SKIPPED \] \([0-9][0-9]*\) tests\?, listed below:/\1/p' | tail -n1)
total=${total:-0}; passed=${passed:-0}; failed=${failed:-0}; skipped=${skipped:-0}

# A real run executes hundreds of cases; zero parsed tests (crash, early exit, neutered binary) is a failure.
if [ "$total" -lt 100 ]; then
  echo "test.sh: only $total tests ran (expected hundreds) — treating as failure" >&2
  failed=$(( failed + 1 ))
fi
[ "$rc" -eq 0 ] || [ "$failed" -gt 0 ] || failed=1

# ReaderTest: decodes every sample set in test/samples against its expected text/format and returns the
# number of failed expectations; it must have processed all the sample directories.
rout=$("$reader" "$SRC/test/samples" 2>&1); rrc=$?
printf '%s\n' "$rout" | tail -n 8
nsets=$(printf '%s\n' "$rout" | grep -c '^[^ ].* [0-9][0-9]* images ')
nexpected=$(find test/samples -mindepth 1 -maxdepth 1 -type d | wc -l)
if [ "$rrc" -eq 0 ] && [ "$nsets" -ge "$nexpected" ] && [ "$nexpected" -gt 0 ]; then passed=$(( passed + 1 ))
else echo "test.sh: ReaderTest failed (rc=$rrc, $nsets of $nexpected sample sets reported)" >&2; failed=$(( failed + 1 )); fi

# WriterTest: encodes barcodes of every creatable format to PNGs in its cwd; it must exit 0 and write them.
wdir=$(mktemp -d)
(cd "$wdir" && "$SRC/$writer"); wrc=$?
npng=$(find "$wdir" -name '*.png' -size +0 | wc -l)
rm -rf "$wdir"
if [ "$wrc" -eq 0 ] && [ "$npng" -ge 10 ]; then passed=$(( passed + 1 ))
else echo "test.sh: WriterTest failed (rc=$wrc, $npng PNGs written)" >&2; failed=$(( failed + 1 )); fi

emit_ctrf cmake-gtest "$passed" "$failed" "$skipped"
