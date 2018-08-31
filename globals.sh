#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Servers
CLR_PUBLIC_DL_URL=${CLR_PUBLIC_DL_URL:-"https://download.clearlinux.org"}

# Variables Cache
VARS_DIR="${WORK_DIR:-$PWD}/.vars"

MIX_INCREMENT=${MIX_INCREMENT:-10}

BUILD_FILE=build-env
PKG_LIST_FILE=packages-nvr
RELEASE_NOTES=release-notes
