#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation

# shellcheck source=globals.sh
# shellcheck source=common.sh

# MCA_VERSIONS: Space separated list of versions that MCA will execute.
#               It will compare each pair of adjacent versions in the list.
#               If MCA_VERSIONS contains a single version, it will not run.

set -e
set -o pipefail

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../globals.sh"
. "${SCRIPT_DIR}/../common.sh"

. ./config/config.sh

var_load MCA_VERSIONS

# shellcheck disable=2206
mca_versions=(${MCA_VERSIONS}) # Make an array

# ==============================================================================
# MAIN
# ==============================================================================
stage "Manifest Correctness Assurance"

if (( ${#mca_versions[@]} <= 1 )); then
    log "No previous versions to compare" "Skipping it. First Mix?"
    exit 0
fi

# Perform MCA check for each version against its previous version.
# Format bumps create multiple MCA logs.
pushd "${BUILD_DIR}" > /dev/null
prev_ver="${mca_versions[0]}"
for ver in "${mca_versions[@]:1}"; do
    mca_log="${WORK_DIR}/${MCA_FILE}-${prev_ver}-${ver}.txt"

    section "Report from '${prev_ver}' to '${ver}'"
    log_line

    sudo -E mixer --native build validate --from "${prev_ver}" --to "${ver}" | tee "${mca_log}"

    # Remove cached RPMs that won't be reused
    sudo rm -rf "update/validation/${prev_ver}"

    prev_ver="${ver}"
done
popd > /dev/null
