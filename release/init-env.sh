#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=common.sh

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"

# ==============================================================================
# MAIN
# ==============================================================================
stage "Initialize Environment"

LOG_INDENT=1 fetch_config_repo
. ./config/config.sh

section "Build Environment"
log "Workflow Repository" "$(git remote get-url origin) ($(git rev-parse --short HEAD))"
log "Workflow Config Repository" "$(git -C config remote get-url origin) ($(git -C config rev-parse --short HEAD))"

section "Configuration"
log "Distribution" "${DISTRO_NAME}"
log "Distribution Content/Version URL" "${DISTRO_URL}"

section "Workspace"
log "Namespace" "${NAMESPACE}"
log "Work dir" "${WORK_DIR}"
log "Variables dir" "${VARS_DIR}"
log "Stage dir" "${STAGING_DIR}"
log "Publishing Host" "${PUBLISHING_HOST}"
log "Publishing Root" "${PUBLISHING_ROOT}"

assert_dep rsync
section "Tools"
log "Clear Linux Version (on Builder)" "$(cat /usr/share/clear/version)"
log "Rsync Version" "$(rsync --version 2>&1 | head -1)"
