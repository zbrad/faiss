#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
#
# tuned/publish.sh <variant> — publishes the GitHub release, and only what tuned/release.sh's gates saw.
# release.sh writes a ready-marker (RELEASE_READY_<variant> in tuned/build/<cuda>/releases/) after every gate
# passes; this reads it and refuses unless HEAD, the release notes and each asset still match the hashes
# recorded there. Run tuned/release.sh <variant> first. It publishes nothing else, and it never builds,
# tests, packages or tags.
set -uo pipefail

REPODIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GPU_TUNED_ARG_VARIANT="$1"

# shellcheck source=env.sh
source "${REPODIR}/tuned/env.sh" "${GPU_TUNED_ARG_VARIANT}" || exit 1
cd "${REPODIR}"

RELEASES_DIR="$(gpu_tuned_out_dir releases "${REPODIR}" "${FAISS_CUDA_TAG}" "${GPU_TUNED_VARIANT}")"
RELEASE_MARKER="${RELEASES_DIR}/RELEASE_READY_${GPU_TUNED_VARIANT}"

gpu_tuned_publish_ready "${RELEASE_MARKER}" || exit 1
TAG="$(sed -n 's/^tag=//p' "${RELEASE_MARKER}.published")"
echo "Release: https://github.com/zbrad/faiss/releases/tag/${TAG}"
