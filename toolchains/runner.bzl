"""Run ordinary cc_test targets through Mull when its setting is enabled."""

def _run(ctx, binary_info, processed_environment, runner, config):
    launcher = ctx.actions.declare_file(ctx.label.name + ".mull.sh")
    ctx.actions.write(launcher, """#!/usr/bin/env bash
set -euo pipefail
export MULL_CONFIG="${TEST_SRCDIR}/${TEST_WORKSPACE}/%s"
exec "${TEST_SRCDIR}/${TEST_WORKSPACE}/%s" \
    --reporters SQLite \
    --report-dir "${TEST_UNDECLARED_OUTPUTS_DIR}" --report-name mull \
    --workers "${TEST_CPUS:-1}" \
    "${TEST_SRCDIR}/${TEST_WORKSPACE}/%s" -- "$@"
""" % (config.short_path, runner.short_path, binary_info.executable.short_path), is_executable = True)
    return [
        DefaultInfo(
            executable = launcher,
            files = depset([launcher], transitive = [binary_info.files]),
            runfiles = binary_info.runfiles.merge(ctx.runfiles(files = [runner, config, binary_info.executable])),
        ),
        RunEnvironmentInfo(environment = processed_environment, inherited_environment = ctx.attr.env_inherit),
    ]

def _runner_impl(ctx):
    return [platform_common.ToolchainInfo(cc_test_info = struct(
        get_runner = struct(func = _run, args = {"runner": ctx.file.runner, "config": ctx.file.config}),
        # Tests can disable their own mutation while depending on instrumented code.
        linkopts = ["-fprofile-instr-generate"],
        linkstatic = True,
    ))]

mull_test_runner = rule(
    implementation = _runner_impl,
    attrs = {
        "runner": attr.label(allow_single_file = True, cfg = "exec", mandatory = True),
        "config": attr.label(allow_single_file = True, mandatory = True),
    },
)
