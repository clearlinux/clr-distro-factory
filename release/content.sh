#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=globals.sh
# shellcheck source=common.sh

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../globals.sh"
. "${SCRIPT_DIR}/../common.sh"

. ./config/config.sh

# ==============================================================================
# MAIN
# ==============================================================================
stage "Finalizing Content"

log_line "Building package list:"
# If no content providers fetched packages, this will act as 'touch'
# shellcheck disable=2086
cat ${WORK_DIR}/${PKG_LIST_TMP}* > "${WORK_DIR}/${PKG_LIST_FILE}" 2>/dev/null || true
log_line "OK!" 1

section "Creating Content Repository"
if [[ -z "$(ls -A "${PKGS_DIR}")" ]]; then
    info "Custom Content Not Found" " '${PKGS_DIR}' is empty."
    exit 0
fi

log_line # Output too verbose
createrepo_c "${REPO_DIR}/x86_64/os" # TODO: log create_repo output and only print its result
log_line
