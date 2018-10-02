#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))

. ${SCRIPT_DIR}/../globals.sh
. ${SCRIPT_DIR}/../common.sh

. ./config/config.sh

# ==============================================================================
# MAIN
# ==============================================================================
stage "Finalizing Content"

if [[ -z "$(ls -A ${PKGS_DIR})" ]]; then
    info "Custom Content Not Found" " '${PKGS_DIR}' is empty."
    exit 0
fi

section "Creating Content Repository"
pushd ${PKGS_DIR} > /dev/null
log_line
createrepo_c ${PKGS_DIR} # Output too verbose
log_line
popd > /dev/null
