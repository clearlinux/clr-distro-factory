#!/usr/bin/env bash
# Copyright (c) 2017 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Servers
CLR_PUBLIC_DL_URL=${CLR_PUBLIC_DL_URL:-"https://download.clearlinux.org"}
PKG_LIST_FILE="custom-pkg-list"

# Variables Cache
VARS_DIR="${WORK_DIR:-$PWD}/.vars"
MIX_INCREMENT=${MIX_INCREMENT:-10}
BUILD_FILE=build-env
RELEASE_NOTES=release-notes
