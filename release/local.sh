#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=common.sh

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"

. ./config/config.sh

# ==============================================================================
# MAIN
# ==============================================================================
stage "Content Provider - local"

pkg_list="${WORK_DIR}/${PKG_LIST_TMP}local"

if [[ -n ${LOCAL_RPM_PATH} && -d ${LOCAL_RPM_PATH} ]]; then
    log_line "Copying local packages from ${LOCAL_RPM_PATH}"
    cp "${LOCAL_RPM_PATH}"/*.rpm "${PKGS_DIR}"/
    for file in "${LOCAL_RPM_PATH}"/*.rpm; do
        rpm=$(basename "$file" .rpm)
        echo "${rpm%.*}" >> "${pkg_list}"
    done
else
    log_line "No LOCAL_RPM_PATH defined."
fi
