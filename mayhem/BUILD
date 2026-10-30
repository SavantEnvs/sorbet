# Fuzz targets for the Mayhem integration. mayhem/build.sh builds them with --check_visibility=false so
# the upstream //test/fuzz:fuzz_dash_e_impl (visible only to //tools) can be linked unchanged.
# lsan_off.cc turns LeakSanitizer off at build time. standalone_main.c is a copy of the base image's
# $STANDALONE_FUZZ_MAIN that build.sh drops here before building the *_standalone reproducers.
# The libFuzzer engine flag arrives through --define=LIB_FUZZING_ENGINE.
cc_binary(
    name = "fuzz_dash_e",
    testonly = 1,
    srcs = ["lsan_off.cc"],
    linkopts = ["$(LIB_FUZZING_ENGINE)"],
    tags = ["manual"],
    deps = ["//test/fuzz:fuzz_dash_e_impl"],
)

cc_binary(
    name = "fuzz_dash_e_standalone",
    testonly = 1,
    srcs = [
        "lsan_off.cc",
        "standalone_main.c",
    ],
    tags = ["manual"],
    deps = ["//test/fuzz:fuzz_dash_e_impl"],
)

cc_binary(
    name = "fuzz_doc_symbols",
    testonly = 1,
    srcs = [
        "fuzz_doc_symbols.cc",
        "lsan_off.cc",
    ],
    linkopts = ["$(LIB_FUZZING_ENGINE)"],
    tags = ["manual"],
    deps = [
        "//core",
        "//main/lsp",
        "//payload",
        "//test/helpers",
    ],
)

cc_binary(
    name = "fuzz_doc_symbols_standalone",
    testonly = 1,
    srcs = [
        "fuzz_doc_symbols.cc",
        "lsan_off.cc",
        "standalone_main.c",
    ],
    tags = ["manual"],
    deps = [
        "//core",
        "//main/lsp",
        "//payload",
        "//test/helpers",
    ],
)
