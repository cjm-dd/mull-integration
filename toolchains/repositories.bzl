"""Expose the public Mull installation provided by the example container."""

def _mull_installation_impl(ctx):
    for source, destination in {
        "/usr/lib/mull-ir-frontend-19": "lib/mull-ir-frontend-19",
        "/usr/bin/mull-runner-19": "bin/mull-runner-19",
        "/usr/lib/x86_64-linux-gnu/libLLVM.so.19.1": "lib/libLLVM.so.19.1",
        "/usr/lib/x86_64-linux-gnu/libclang-cpp.so.19.1": "lib/libclang-cpp.so.19.1",
    }.items():
        if not ctx.path(source).exists:
            fail("Missing %s. Run this example in the documented container." % source)
        ctx.symlink(source, destination)
    ctx.file("BUILD.bazel", """package(default_visibility = ["//visibility:public"])
exports_files(["bin/mull-runner-19", "lib/mull-ir-frontend-19"])
filegroup(name = "compiler_files", srcs = glob(["lib/*"]))
""")

mull_installation = repository_rule(
    implementation = _mull_installation_impl,
    local = True,
)
