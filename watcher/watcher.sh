#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=globals.sh
# shellcheck source=common.sh

set -e

# return codes:
# 0 = We are up-to-date. Pipeline Success.
# 1 = A new release is needed. Pipeline Unstable.
# > 1 = Errors. Pipeline Failure.

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../globals.sh"
. "${SCRIPT_DIR}/../common.sh"

echo "=== Watcher"
fetch_config_repo
. ./config/config.sh

echo "Upstream Server:"
echo "    ${CLR_PUBLIC_DL_URL}"
echo "Downstream Stage:"
echo "    ${STAGING_DIR}"
echo

# Check if we are on track with Upstream ClearLinux
get_latest_versions

echo "Clear Linux version:"
echo "    $CLR_LATEST"
echo "Downstream version:"
if [[ -z $DS_LATEST ]]; then
    echo "    First Mix! It's Release Time!"
    exit 1
fi
echo "    $DS_UP_VERSION $DS_DOWN_VERSION"

if (( DS_UP_VERSION < CLR_LATEST )); then
    echo "Upstream has a new release. It's Release Time!"
    exit 1
fi

# Check if is there new custom content to be released
ret=0
TMP_PREV_LIST=$(mktemp)
TMP_CURR_LIST=$(mktemp)
PKG_LIST_PATH=${STAGING_DIR}/releases/${DS_LATEST}/${PKG_LIST_FILE}-${DS_LATEST}.txt

if ! cat "${PKG_LIST_PATH}" > "${TMP_PREV_LIST}"; then
    echo "Wrn: Failed to fetch Downstream PREVIOUS Package List. Assuming empty."
fi

if result=$(koji_cmd list-tagged --latest --quiet "${KOJI_TAG}"); then
    echo "${result}" | awk '{print $1}' > "${TMP_CURR_LIST}"
else
    echo "Wrn: Failed to fetch Downstream Package List. Assuming empty."
fi

if ! diff "${TMP_CURR_LIST}" "${TMP_PREV_LIST}"; then
    echo "New custom content. It's Release Time!"
    ret=1
else
    echo "Nothing to see here."
fi

rm "${TMP_CURR_LIST}"
rm "${TMP_PREV_LIST}"
exit ${ret}
