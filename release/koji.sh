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
stage "Content Provider - Koji"

pkg_list="${WORK_DIR}/${PKG_LIST_TMP}koji"

log_line "Fetching Package List:"
if result=$(koji_cmd list-tagged --latest --quiet "${KOJI_TAG}"); then
    awk '{print $1}' <<< "${result}" > "${pkg_list}"
else
    log_line "No custom content was found." 1
    exit 0
fi
log_line "OK!" 1

section "Downloading RPMs"
pushd "${PKGS_DIR}" > /dev/null
for rpm in $(cat "${pkg_list}"); do
    log_line "${rpm}:"
    koji_cmd download-build -a x86_64 --quiet "${rpm}"
    log_line "OK!" 1
done
popd > /dev/null
