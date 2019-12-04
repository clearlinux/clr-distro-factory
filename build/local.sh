#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=common.sh

# LOCAL_RPM_DIR: Folder containing RPMs that should be part of a release.

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"

. ./config/config.sh

# ==============================================================================
# MAIN
# ==============================================================================
stage "Content Provider - Local Folder"

pkg_list="${WORK_DIR}/${PKG_LIST_TMP}local"
true > "${pkg_list}"

if [[ -n ${LOCAL_RPM_DIR} && -d ${LOCAL_RPM_DIR} ]]; then
    log "RPMs Folder" "${LOCAL_RPM_DIR}"
    log_line

    rpms=$(find "${LOCAL_RPM_DIR}/" \
        -iname "*.rpm" -type f -printf '%f ' 2>/dev/null || true)

    for rpm in ${rpms}; do
        log_line "Copying '${rpm}':"
        cp "${LOCAL_RPM_DIR}/${rpm}" "${PKGS_DIR}" 2>/dev/null
        log_line "OK!" 1
        basename "$rpm" ".rpm" >> "${pkg_list}"
    done
else
    warn "Custom Content Not Found" "'LOCAL_RPM_DIR' not defined."
fi
