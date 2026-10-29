# fuzzReadMatrix: float-cast-overflow (NaN to int) in `LocalGrid`

Reproducer: `ubsan-nan-to-int-LocalGrid.bin` (run it through `/mayhem/fuzzReadMatrix-standalone`).
Kept out of `testsuite/` on purpose: seeds are replayed every run.

- Report: `core/src/LocalGrid.cpp:46:18: runtime error: nan is outside the range of representable values of type 'int'`
- Cause: `LocalGrid::adjustOriginAndStep` does `int limit = int(6 * modSize)` where `modSize = length(step)` is NaN for a degenerate step.
- Impact: undefined behaviour (halting under `-fsanitize=undefined -fno-sanitize-recover=all`); the converted
  `limit` is unspecified.
- Fix: reject a non-finite `step` before the conversion.
- Found at upstream `d7c8e072` within seconds of fuzzing, with the default harness and no seeds.
