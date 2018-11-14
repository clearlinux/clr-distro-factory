#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

# shellcheck source=common.sh
. "${SCRIPT_DIR}/../common.sh"
. ./config/config.sh

REMOTE_PATH=${PUBLISHING_HOST}:${PUBLISHING_ROOT}/${NAMESPACE:-${DSTREAM_NAME}}

stage "PUBLISH"
log "From" "${STAGING_DIR}"
log "To" "${REMOTE_PATH}"

section "Syncing Content"
assert_dir "${STAGING_DIR}"
rsync -vrlHpt --safe-links --delete --exclude '*.src.rpm' -e ssh "${STAGING_DIR}/" "${REMOTE_PATH}"
