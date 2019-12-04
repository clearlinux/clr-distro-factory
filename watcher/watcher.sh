#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=common.sh

set -e

# return codes:
# 0 = We are up-to-date. Pipeline Success.
# 1 = A new build is needed. Pipeline Unstable.
# > 1 = Errors. Pipeline Failure.

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"

# ==============================================================================
# MAIN
# ==============================================================================
stage "Watcher"
fetch_config_repo
. ./config/config.sh

log "Upstream Server" "${CLR_PUBLIC_DL_URL}"
log "Distribution Stage" "${STAGING_DIR}"
log_line

# Check if we are on track with Upstream ClearLinux
get_latest_versions

log "Clear Linux version" "${CLR_LATEST}"
log "Distribution version"
if [[ -z "${DS_LATEST}" ]]; then
    log_line "First Mix! It's Build Time!" 1
    exit 1
fi
log_line "${DS_UP_VERSION} ${DS_DOWN_VERSION}" 1

if (( DS_UP_VERSION < CLR_LATEST )); then
    log "Upstream has a new release" "It's Build Time!"
    exit 1
fi

# Check if is there new custom content to be built
ret=0
TMP_PREV_LIST=$(mktemp)
TMP_CURR_LIST=$(mktemp)
PKG_LIST_PATH="${STAGING_DIR}/releases/${DS_LATEST}/${PKG_LIST_FILE}-${DS_LATEST}.txt"

if ! cat "${PKG_LIST_PATH}" > "${TMP_PREV_LIST}"; then
    warn "Failed to fetch Distribution PREVIOUS Package List" "Assuming empty"
fi

if result=$(koji_cmd list-tagged --latest --quiet "${KOJI_TAG}"); then
    echo "${result}" | awk '{print $1}' > "${TMP_CURR_LIST}"
else
    warn "Failed to fetch Distribution Package List" "Assuming empty."
fi

if ! diff "${TMP_CURR_LIST}" "${TMP_PREV_LIST}"; then
    log "New custom content" "It's Build Time!"
    ret=1
else
    log "Nothing to see here."
fi

rm "${TMP_CURR_LIST}"
rm "${TMP_PREV_LIST}"
exit ${ret}
