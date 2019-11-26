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
pkg_list_files="${WORK_DIR}/${PKG_LIST_TMP}local-files"
true > "${pkg_list}"

if [[ -n ${LOCAL_RPM_DIR} && -d ${LOCAL_RPM_DIR} ]]; then
    log "RPMs Folder" "${LOCAL_RPM_DIR}"
    log_line

    find "${LOCAL_RPM_DIR}/" -iname "*.rpm" -type f > "${pkg_list_files}"
    xargs -I {} -a "${pkg_list_files}" cp {} "${PKGS_DIR}"
    sed -r -e 's|(\w+/)+||' -e 's|^/||' -e 's/\.rpm$//' "${pkg_list_files}" > "${pkg_list}"
else
    warn "Custom Content Not Found" "'LOCAL_RPM_DIR' not defined."
fi
