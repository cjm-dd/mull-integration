FROM debian:13-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

# This example targets Linux x86_64. Compiler and plugin share Debian's libLLVM.
RUN test "$(dpkg --print-architecture)" = amd64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl python3 unzip zip file g++ \
        clang-19=1:19.1.7-3+b1 llvm-19=1:19.1.7-3+b1 \
        lld-19=1:19.1.7-3+b1 libclang-rt-19-dev=1:19.1.7-3+b1 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 3 -o /tmp/mull.deb \
        https://github.com/mull-project/mull/releases/download/0.34.0/Mull-19-0.34.0-LLVM-19.1.7-debian-amd64-13.deb \
    && echo '7be58232cd8dab2dc76370263b330d61bef50de71acfe0c62f3f004fffba5c06  /tmp/mull.deb' | sha256sum -c - \
    && dpkg -i /tmp/mull.deb \
    && rm /tmp/mull.deb

RUN curl -fsSL --retry 3 -o /usr/local/bin/bazel \
        https://github.com/bazelbuild/bazel/releases/download/8.4.2/bazel-8.4.2-linux-x86_64 \
    && echo '4dc8e99dfa802e252dac176d08201fd15c542ae78c448c8a89974b6f387c282c  /usr/local/bin/bazel' | sha256sum -c - \
    && chmod +x /usr/local/bin/bazel

WORKDIR /workspace
CMD ["bash", "tools/check.sh"]
