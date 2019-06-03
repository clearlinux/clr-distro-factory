#!/usr/bin/env bash
# Copyright (C) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

NAMESPACE=${NAMESPACE:?"NAMESPACE cannot be Null/Unset"}
WORK_DIR=${WORK_DIR:-"${PWD}/${NAMESPACE}/work"}

# Servers
CLR_PUBLIC_DL_URL=${CLR_PUBLIC_DL_URL:-"https://download.clearlinux.org"}

# Mixer
MIX_INCREMENT=${MIX_INCREMENT:-10}

# Workspace
LOG_DIR="${WORK_DIR}/logs"
REPO_DIR="${WORK_DIR}/repo"
VARS_DIR="${WORK_DIR}/.vars"

BUILD_ARCH="${BUILD_ARCH:-x86_64}"
PKGS_DIR="${REPO_DIR}/${BUILD_ARCH}/os/packages"
PKGS_DIR_SUFFIX="repo/${BUILD_ARCH}/os/packages"

BUILD_FILE=build-env
BUNDLES_FILE=bundles-def
CONTENT_REPO=content
MCA_FILE=mca-report
PKG_LIST_FILE=packages-nvr
PKG_LICENSES_FILE=packages-license-info
PKG_LIST_TMP=packages_
RELEASE_NOTES=release-notes

# List of words to be filtered out from $PKG_LICENSES_FILE as they are not real licenses
# Space-separated
LICENSES_FILTER=${LICENSES_FILTER-"and"}
