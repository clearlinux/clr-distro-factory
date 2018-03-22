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

set -e

# return codes:
# 0 = We are up-to-date. Pipeline Success.
# 1 = A new release is needed. Pipeline Unstable.
# > 1 = Errors. Pipeline Failure.

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))

. ${SCRIPT_DIR}/../globals.sh
. ${SCRIPT_DIR}/../common.sh

fetch_config_repo
. ./config/config.sh

echo "=== Watcher"
echo "Upstream Server= ${CLR_PUBLIC_DL_URL}"
echo "Downstream Server= ${DSTREAM_DL_URL}"

# Check if we are on track with Upstream ClearLinux
CLR_LATEST=$(curl ${CLR_PUBLIC_DL_URL}/latest) || true
if [[ -z $CLR_LATEST ]]; then
    echo "Error: Failed to fetch Clear Linux latest version."
    exit 2
fi

DS_LATEST=$(curl ${DSTREAM_DL_URL}/latest) || true
if [ -z $DS_LATEST ]; then
    echo "Error: Failed to fetch Downstream Clear Linux latest version."
    exit 2
elif ((${#DS_LATEST} < 4)); then
    echo "Error: Downstream Clear Linux version number seems corrupted."
    exit 2
fi

DS_UP_VERSION=${DS_LATEST: : -3}
DS_DOWN_VERSION=${DS_LATEST: -3}

echo "Clear Linux version: $CLR_LATEST"
echo "Downstream version:  $DS_UP_VERSION $DS_DOWN_VERSION"

if (($DS_UP_VERSION < $CLR_LATEST)); then
    echo "Upstream has a new release. It's Release Time!"
    exit 1
fi

# Check if is there new custom content to be released
ret=0
TMP_PREV_LIST=$(mktemp)
TMP_CURR_LIST=$(mktemp)
PKG_LIST_PATH=${DSTREAM_DL_URL}/update/${DS_LATEST}/${PKG_LIST_FILE}

if ! curl ${PKG_LIST_PATH} -o ${TMP_PREV_LIST}; then
    echo "Wrn: Failed to fetch Downstream PREVIOUS Package List. Assuming empty."
fi

if result=$(koji_cmd list-tagged --latest --quiet ${KOJI_TAG}); then
    echo "${result}" | awk '{print $1}' > ${TMP_CURR_LIST}
else
    echo "Wrn: Failed to fetch Downstream Package List. Assuming empty."
fi

if ! diff ${TMP_CURR_LIST} ${TMP_PREV_LIST}; then
    echo "New custom content. It's Release Time!"
    ret=1
else
    echo "Nothing to see here."
fi

rm ${TMP_CURR_LIST}
rm ${TMP_PREV_LIST}
exit ${ret}
