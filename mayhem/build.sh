#!/usr/bin/env bash
#
# mayhem/build.sh — build zxing-cpp's five upstream libFuzzer harnesses (test/fuzz/*.cpp) with the
# sanitized, DWARF-3 library, plus the project's own GoogleTest suite with NORMAL flags for test.sh.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS SRC

cd "$SRC"

# 1) Sanitized + SanCov-instrumented library and the harnesses. -fsanitize=fuzzer-no-link goes on the
#    library compile unconditionally so the fuzzed code has edge coverage (also in the no-sanitizer build).
# Always configure fresh: the Dockerfile build resolves clang through the ccache masquerade dir, a re-run
# resolves it directly, and CMake then discards the cache (and with it the -D settings) mid-configure.
rm -rf build/fuzz build/tests
FUZZ_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -O1"
cmake -G Ninja -S mayhem/fuzz -B build/fuzz \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_BUILD_TYPE= \
    -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
    -DZX_SRC="$SRC" -DOUT_DIR="$SRC" -DLSAN_OFF="$SRC/mayhem/lsan_off.cc"
cmake --build build/fuzz -j"$MAYHEM_JOBS"

# 2) The project's own unit tests (GoogleTest from apt), NORMAL flags, left for test.sh to run.
cmake -G Ninja -S . -B build/tests \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
    -DZXING_UNIT_TESTS=ON -DZXING_WRITERS=BOTH -DZXING_READERS=ON \
    -DZXING_EXAMPLES=OFF -DZXING_C_API=OFF -DZXING_DEPENDENCIES=LOCAL \
    -DBUILD_SHARED_LIBS=OFF
cmake --build build/tests -j"$MAYHEM_JOBS" --target UnitTest
