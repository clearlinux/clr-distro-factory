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
stage "Content Provider - Preparing local rpms"


local_pkgs_dir="$HOME/local-rpms/"
pkg_list="${WORK_DIR}/${PKG_LIST_TMP}local"

log_line "Fetching Package List from ${local_pkgs_dir}"
if [ -d ${local_pkgs_dir} ]; then
    for file in $(ls ${local_pkgs_dir}/*.rpm); do
        rpm=$(basename $file .rpm)
    	echo ${rpm%.*} >> ${pkg_list}
    done
else
    log_line "No custom content was found."
fi

log_line "local rpms:"
cat ${pkg_list}
log_line "OK!" 1

section "Copying RPMs"
cp ${local_pkgs_dir}/*.rpm ${PKGS_DIR}
log_line "OK!" 1
