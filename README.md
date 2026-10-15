# Mull with Bazel and toolchains_llvm

A standalone Linux x86_64 example of [Mull](https://github.com/mull-project/mull)
mutation testing with ordinary Bazel `cc_test` targets. It uses
[toolchains_llvm](https://github.com/bazel-contrib/toolchains_llvm) to configure
Clang, [rules_cc](https://github.com/bazelbuild/rules_cc) to define the compiler
feature, and [GoogleTest](https://github.com/google/googletest) for the example
assertions. All dependencies come from public upstream releases, Debian, or the
[Bazel Central Registry](https://registry.bazel.build/).

The example pins Mull 0.34.0, Clang 19.1.7, Bazel 8.4.2, and toolchains_llvm
1.11.3. The container supplies compatible compiler and plugin binaries;
`toolchains_llvm` owns the Bazel C++ toolchain configuration.

## Run the example

Install Docker, then run from this checkout:

```sh
docker build --platform=linux/amd64 -t mull-integration-example .
docker run --rm --platform=linux/amd64 \
  --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD:/workspace" mull-integration-example
```

The default command runs `tools/check.sh`. It checks that:

- Both test targets pass without Mull.
- `strong_test` kills both covered mutations, including a floating-point change.
- `weak_test` fails mutation testing because one mutation survives. This failure
  is intentional: the script requires Bazel's test-failure exit code, then
  continues to generate its report.
- A third mutation exists in the binary but is skipped because its function is
  not executed during the coverage warmup.
- Test arguments, environment variables, and data runfiles remain usable.
- A C++ header generator builds in the exec configuration without Mull.
- Turning `enable_mull` off restores normal test execution.

The overall command exits successfully only if these expectations hold. It
writes ignored artifacts under `reports/strong/` and `reports/weak/`.

For individual commands, open a shell in the same image:

```sh
docker run --rm -it --platform=linux/amd64 \
  --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD:/workspace" mull-integration-example bash

bazel --nohome_rc test //examples:strong_test
bazel --nohome_rc test --config=mull //examples:strong_test
bazel --nohome_rc test --config=mull //examples:weak_test  # Expected failure.
bazel --nohome_rc test --config=mull --enable_mull=false //examples:strong_test
```

`--nohome_rc` keeps unrelated user settings out of this example. The test runner
produces `mull.sqlite` in each test's undeclared outputs; it does not add source
files to the test's runfiles.

## Toolchain integration

[`MODULE.bazel`](MODULE.bazel) declares two toolchains through the upstream LLVM
module extension. Both use the same Debian LLVM installation through
`llvm.toolchain_root`. The Mull variant adds:

- `extra_enabled_features = ["//toolchains:mull"]`, a `cc_feature` containing
  plugin loading, debug information, and LLVM coverage instrumentation;
- `extra_compiler_files`, which declares the plugin, its shared LLVM/Clang
  libraries, and `mull.yml` as compiler inputs;
- a `target_settings` predicate requiring `enable_mull`.

The separate C++ test runner toolchain uses the same predicate. Bazel platform
constraints describe Linux/x86_64 compatibility; configurable build settings
belong in `target_settings`, not `target_compatible_with`.

The `cc_feature` bridge in this toolchains_llvm release does **not** automatically
propagate `cc_args.data` into compiler inputs, so the explicit
`extra_compiler_files` declaration matters. There is no hand-maintained C++
compiler configuration in this repository.

`.bazelrc` provides `--config=mull`. It enables the setting, keeps debug
information, selects static linking for C++ dependencies, and uses
`--experimental_exclude_starlark_flags_from_exec_config` to keep the setting out
of build tools' execution configurations.

The test targets use `features = ["-mull"]` to preserve their assertions while
instrumenting the library under test. The runner links the profiling runtime
for those tests. `mull.yml` limits mutation to example production sources,
excludes external repositories and test source files, and selects one mutation
operator to keep the demonstration deterministic.

### LLVM compatibility

The compiler and plugin must use compatible LLVM builds. The public Debian
Mull package depends on `libLLVM.so.19.1` and `libclang-cpp.so.19.1`, provided by
the same Debian LLVM 19 packages used by Clang. This avoids loading an unrelated
LLVM runtime into the compiler process.

The Docker base image is pinned by digest. Mull and Bazel downloads are checked
against SHA-256 digests, LLVM packages have explicit versions, and Bzlmod locks
public module dependencies. Debian's remaining package dependencies still come
from its package repositories. This is a container-based example, **not a fully
hermetic compiler/sysroot distribution**: the generated toolchain uses system
paths inside the image. Remote execution would need a matching execution image
or a packaged compiler, runtime, and sysroot declared as Bazel inputs. Native
execution on an older host libc is not supported; use the container.

## Read the results

Render a test's SQLite artifact from the **same, unmodified source checkout**:

```sh
python3 tools/report.py \
  bazel-testlogs/examples/weak_test/test.outputs/mull.sqlite reports/weak
```

Run this command inside the example container, where `mull-reporter-19` is
installed. It preserves the raw artifact and creates a report copy with
repository-relative source paths. Report outputs are:

| File | Use |
| --- | --- |
| `mull.txt` | Source-backed textual findings. |
| `mull.sqlite` | Normalized raw execution results for further analysis. |
| `mull.json` and `mull.html` | Mutation Testing Elements source browser. |
| `mull.sarif` | Surviving findings for SARIF viewers and editor navigation. |

Serve the reports from the host:

```sh
python3 -m http.server --bind 127.0.0.1 8000 --directory reports
```

Open port 8000 on your machine and navigate to `weak/mull.html`. The HTML loads the pinned, public
Mutation Testing Elements 3.9.0 JavaScript from unpkg, so viewing it requires
network access. The JSON includes source snippets read during report rendering.
SARIF contains surviving/uncovered findings, not a complete execution ledger.

Compilation uses `/workspace` for debug and coverage paths, matching the
container mount point. Unmodified Mull needs these source paths to exist while
compiling. The report script replaces this prefix in **both** filenames and
mutation IDs in a copy of the SQLite database, then invokes the upstream
reporters from the checkout. No custom Mull build or patch is required. If you
change the container mount point, update the compilation directory and report
prefix together.

Treat a surviving mutation as a specific question about an assertion: here,
`increment(2.0) > 0.0` accepts both `+1.0` and `-1.0`. The strong test checks the
actual expected value. Uncovered mutations are filtered before execution and
are absent from these reports; the reported score concerns the two executed
mutations. This example renders each test separately and does not aggregate
results across test targets, configurations, or revisions.

## References

- [Mull 0.34.0 release](https://github.com/mull-project/mull/releases/tag/0.34.0)
- [Mull runner options](https://mull.readthedocs.io/en/latest/command-line/mull-runner.html)
- [Controlling mutations](https://mull.readthedocs.io/en/latest/tutorials/ControlMutationsTutorial.html)
- [toolchains_llvm: bring your own LLVM](https://github.com/bazel-contrib/toolchains_llvm#bring-your-own-llvm)
- [Mutation Testing Elements](https://github.com/stryker-mutator/mutation-testing-elements)
