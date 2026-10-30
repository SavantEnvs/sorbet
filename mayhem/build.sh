#!/usr/bin/env bash
#
# mayhem/build.sh — build Sorbet's fuzz harnesses (sanitized), their -standalone reproducers, and the
# normal-flag `sorbet` binary that mayhem/test.sh drives. Runs in the commit image as `mayhem` in /mayhem.
#
# Bazel is pinned under /opt/toolchains/bazel (binary, output tree with the downloaded LLVM toolchain and
# every external repo, repository cache) so the air-gapped PATCH re-run resolves everything locally and
# only rebuilds what a patch touched. The sanitized and normal builds use different --platform_suffix
# output trees, so they do not invalidate each other.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"

TC=/opt/toolchains/bazel
mkdir -p "$TC"
export bazel_bin_loc="$TC/binaries"
BAZEL=(./bazel --output_user_root="$TC/root")
REPO=(--repository_cache="$TC/repo-cache")
COMMON=("${REPO[@]}" --jobs="$MAYHEM_JOBS" --spawn_strategy=local --genrule_strategy=local
        --check_visibility=false --strip=never)

# 1) Fetch every external repo (online on the first run, a no-op from the caches afterwards), then slim
#    the downloaded LLVM toolchain: the image only needs clang, lld and a few binutils, not flang/mlir/lldb.
"${BAZEL[@]}" fetch "${REPO[@]}" //mayhem:fuzz_dash_e //mayhem:fuzz_doc_symbols //main:sorbet

OUTPUT_BASE="$("${BAZEL[@]}" info "${REPO[@]}" output_base)"
LLVM="$OUTPUT_BASE/external/llvm_toolchain_22_1_3_llvm"
if [ -d "$LLVM" ]; then
  (
    cd "$LLVM/bin"
    rm -f -- mlir-* flang* bbc fir-* tco clang-repl clang-check clang-tidy clang-linker-wrapper \
      clang-nvlink-wrapper clang-sycl-linker clang-extdef-mapping clangd clang-query clang-refactor \
      clang-change-namespace clang-include-cleaner clang-move clang-doc find-all-symbols \
      clang-reorder-fields clang-include-fixer clang-scan-deps clang-installapi c-index-test \
      modularize pp-trace opt llc lli bugpoint llvm-lto llvm-lto2 llvm-reduce llvm-ir2vec llvm-c-test \
      llvm-dwarfutil lldb* llvm-split llvm-gsymutil llvm-exegesis llvm-bolt* llvm-jitlink \
      llvm-cfi-verify llvm-profgen llvm-debuginfo-analyzer llvm-mca llvm-ml dsymutil sancov
    # Dangling symlinks left behind by the removals above.
    find . -xtype l -delete
  )
  # Top-level lib/ only holds LLVM/Clang/MLIR/Flang libraries; libc++ and the clang runtimes live in
  # subdirectories.
  find "$LLVM/lib" -maxdepth 1 \( -type f -o -type l \) \( -name '*.a' -o -name '*.so*' \) -delete
  rm -rf "$LLVM/lib/cmake" "$LLVM/lib/python3.11" "$LLVM/lib/libear" "$LLVM/lib/libscanbuild" \
         "$LLVM/lib/objects-RELEASE"
  # The toolchain's runtime archives (libFuzzer, ASan, libc++, ...) are built with DWARF 5 and would put a
  # DWARF 5 compile unit into every fuzz binary; drop their debug info (the project is built with
  # $DEBUG_FLAGS, and the runtimes need no source-level triage).
  find "$LLVM/lib" \( -name '*.a' -o -name '*.o' \) -type f -print0 \
    | xargs -0 -r -n 8 llvm-strip --strip-debug
fi

# 2) Sanitized fuzz harnesses + standalone reproducers. mayhem/BUILD compiles mayhem/lsan_off.cc (the
#    __lsan_is_turned_off() hook) into every fuzz and -standalone binary, so LeakSanitizer is off at build time.
FUZZ=(--platform_suffix=mayhem-fuzz --define=LIB_FUZZING_ENGINE="$LIB_FUZZING_ENGINE"
      --copt=-DFORCE_DEBUG --copt=-DSKIP_SLOW_ENFORCE --copt=-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
      --copt=-O1 --copt=-fsanitize=fuzzer-no-link)
case "$SANITIZER_FLAGS" in
  *-fsanitize*) FUZZ+=(--define=unsanitized=false --copt=-DHAS_SANITIZER) ;;
esac
case "$SANITIZER_FLAGS" in
  *address*) FUZZ+=(--copt=-fsanitize-address-use-after-scope --linkopt=-fsanitize-address-use-after-scope
                    --copt=-DADDRESS_SANITIZER) ;;
esac
for w in $SANITIZER_FLAGS $DEBUG_FLAGS; do FUZZ+=(--copt="$w" --linkopt="$w"); done
# Bazel links C++ targets through the C driver; ask for the sanitizer's C++ runtime explicitly.
FUZZ+=(--linkopt=-fsanitize-link-c++-runtime)

cp -f "$STANDALONE_FUZZ_MAIN" "$SRC/mayhem/standalone_main.c"

"${BAZEL[@]}" build "${COMMON[@]}" "${FUZZ[@]}" \
  //mayhem:fuzz_dash_e //mayhem:fuzz_dash_e_standalone \
  //mayhem:fuzz_doc_symbols //mayhem:fuzz_doc_symbols_standalone
FUZZ_BIN="$("${BAZEL[@]}" info "${COMMON[@]}" "${FUZZ[@]}" bazel-bin)/mayhem"
for t in fuzz_dash_e fuzz_dash_e_standalone fuzz_doc_symbols fuzz_doc_symbols_standalone; do
  dst="/mayhem/${t/_standalone/-standalone}"
  cp -f "$FUZZ_BIN/$t" "$dst"
  chmod u+w "$dst"
done

# 3) The `sorbet` CLI with the project's NORMAL flags, for mayhem/test.sh.
TESTFLAGS=(--platform_suffix=mayhem-test)
for w in $COVERAGE_FLAGS; do TESTFLAGS+=(--copt="$w" --linkopt="$w"); done
"${BAZEL[@]}" build "${COMMON[@]}" "${TESTFLAGS[@]}" //main:sorbet
TEST_BIN="$("${BAZEL[@]}" info "${COMMON[@]}" "${TESTFLAGS[@]}" bazel-bin)/main/sorbet"
cp -f "$TEST_BIN" /mayhem/sorbet-oracle
chmod u+w /mayhem/sorbet-oracle
