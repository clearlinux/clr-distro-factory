#!/usr/bin/env bash
# Copyright (C) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

NAMESPACE=${NAMESPACE:?"NAMESPACE cannot be Null/Unset"}
WORK_DIR=${WORK_DIR:-"${PWD}/${NAMESPACE}/work"}

# Distribution
# If this update stream is either a downstream or an upstream
# A Downstream Mix makes reference to an external update stream to reuse content
IS_DOWNSTREAM=${IS_DOWNSTREAM:-true}
# If this build should be a min version
MIN_VERSION=${MIN_VERSION:-false}
# If this build should be a format bump
# Only used by upstream mixes. Downstream mixes can only track upstream mixes
# format bumps, which is automated
FORMAT_BUMP=${FORMAT_BUMP:-false}

# Servers
CLR_PUBLIC_DL_URL=${CLR_PUBLIC_DL_URL:-"https://download.clearlinux.org"}

# Mixer
MIX_INCREMENT=${MIX_INCREMENT:-10}
# Global options to apply to all mixer calls
MIXER_OPTS=${MIXER_OPTS:-""}
# Number of builds from the current build to generate deltas
NUM_DELTA_BUILDS=${NUM_DELTA_BUILDS:-10}
# Supported Mixer Version
MIXER_MAJOR_VER=${MIXER_MAJOR_VER:-6}

# Workspace
BUNDLES_DIR=${BUNDLES_DIR:-"${WORK_DIR}/bundles"}
LOG_DIR="${WORK_DIR}/logs"
REPO_DIR="${WORK_DIR}/repo"
VARS_DIR="${WORK_DIR}/.vars"

BUILD_ARCH="${BUILD_ARCH:-x86_64}"
PKGS_DIR_SUFFIX="${BUILD_ARCH}/os/packages"
PKGS_DIR="${REPO_DIR}/${PKGS_DIR_SUFFIX}"

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

# Images
CHKSUM_FILE_SUFFIX=${CHKSUM_FILE_SUFFIX:-"SHA512SUM"}
