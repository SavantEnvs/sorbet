# syntax=docker/dockerfile:1.7
#
# Commit image for sorbet: the org C/C++ base plus the per-commit Bazel build (mayhem/build.sh).
#
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile --build-arg COMMIT=$(git rev-parse HEAD) -t sorbet .
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (build.sh unsets it when empty); an empty ENV breaks clang.
ARG SOURCE_DATE_EPOCH
# Declared without a default so the base ENV's ASan+UBSan flags flow through unless --build-arg overrides.
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# Bazel's binary, output tree (downloaded LLVM toolchain, external repos, build outputs) and repository
# cache live here so the offline PATCH re-run resolves them from the image.
USER root
RUN mkdir -p /opt/toolchains/bazel && chown 2000:2000 /opt/toolchains/bazel

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# No ccache pre-fill: the Bazel build uses its own absolute-path LLVM toolchain, which ccache cannot wrap.
RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
