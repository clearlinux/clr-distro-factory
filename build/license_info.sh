#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=common.sh

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
. "${SCRIPT_DIR}/../common.sh"
. ./config/config.sh

var_load MIX_VERSION
var_load CLR_LATEST

dnf_conf="${MIXER_DIR}/.yum-mix.conf"

generate_license_info() {
    awk '{print $1}' < "${MIXER_DIR}/update/image/${MIX_VERSION}/os-packages" \
        | xargs dnf --quiet --config "${dnf_conf}" --releasever="${CLR_LATEST:-"clear"}" \
        --installroot="${WORK_DIR}/dnf-cache" repoquery --queryformat "%{LICENSE}" \
        | tr ' ' '\n' \
        | sort -u
}

# ==============================================================================
# MAIN
# ==============================================================================
log "Generating License Info"
generate_license_info > "${WORK_DIR}/${PKG_LICENSES_FILE}"

# Filter out non-license words
for word in ${LICENSES_FILTER}; do
    sed -e "/^${word}$/d" -i "${WORK_DIR}/${PKG_LICENSES_FILE}"
done

log_line "Done!" 1
