cmake_minimum_required(VERSION 3.21)
project(ZXingMayhemFuzz C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(BUILD_SHARED_LIBS OFF)

# Same configuration as upstream's test/fuzz/CMakeLists.txt, minus its hardcoded sanitizer flags
# and -march=native: those come from build.sh via CMAKE_<LANG>_FLAGS.
set(ZXING_WRITERS BOTH)
set(ZXING_READERS ON)
add_definitions(-DZXING_BUILD_FOR_TEST)
add_subdirectory(${ZX_SRC}/core ZXing)

# LLVM's run-once driver is C; keep it a C object so the C++ harness's extern "C" reference links.
add_library(standalone_main OBJECT $ENV{STANDALONE_FUZZ_MAIN})

set(HARNESSES DBEDecoder DMEncoder ReadLinear ReadMatrix DecodeMatrix)
foreach(h ${HARNESSES})
    set(name "fuzz${h}")
    foreach(variant fuzzer standalone)
        if(variant STREQUAL "fuzzer")
            set(exe ${name})
            add_executable(${exe} ${ZX_SRC}/test/fuzz/${name}.cpp ${LSAN_OFF})
            target_link_libraries(${exe} ZXing::ZXing $ENV{LIB_FUZZING_ENGINE})
        else()
            set(exe ${name}-standalone)
            add_executable(${exe} ${ZX_SRC}/test/fuzz/${name}.cpp ${LSAN_OFF}
                           $<TARGET_OBJECTS:standalone_main>)
            target_link_libraries(${exe} ZXing::ZXing)
        endif()
        target_compile_options(${exe} PRIVATE -DZXING_INTERNAL)
        set_target_properties(${exe} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${OUT_DIR})
    endforeach()
endforeach()
