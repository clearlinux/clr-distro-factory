#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Servers
CLR_PUBLIC_DL_URL=${CLR_PUBLIC_DL_URL:-"https://download.clearlinux.org"}

# Workspace
LOG_DIR="${WORK_DIR:-$PWD}/logs"
REPO_DIR="${WORK_DIR:-$PWD}/repo"
VARS_DIR="${WORK_DIR:-$PWD}/.vars"
PKGS_DIR="${REPO_DIR}/x86_64/os/packages"

MIX_INCREMENT=${MIX_INCREMENT:-10}

BUILD_FILE=build-env
BUNDLES_FILE=bundles-def
MCA_FILE=mca-report
PKG_LIST_FILE=packages-nvr
PKG_LIST_TMP=packages_
RELEASE_NOTES=release-notes
