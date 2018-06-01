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

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))

. ${SCRIPT_DIR}/../globals.sh
. ${SCRIPT_DIR}/../common.sh

. ./config/config.sh

var_load MIX_VERSION

IMAGE_TEMPLATE=${IMAGE_TEMPLATE:-"${PWD}/config/release-image-config.json"}

# ==============================================================================
# MAIN
# ==============================================================================
format=$(< ${BUILD_DIR}/update/www/${MIX_VERSION}/format)
if [[ -z "${format}" ]]; then
    error "Failed to fetch Downstream current format."
    exit 1
fi

pushd ${BUILD_DIR} > /dev/null

echo "${IMAGE_TEMPLATE} contents:"
cat ${IMAGE_TEMPLATE}

echo
echo "=== GENERATING RELEASE IMAGE"
tempdir=$(mktemp -d)

sudo -E ister.py -s Swupd_Root.pem -t ${IMAGE_TEMPLATE} \
    -C file://${PWD}/update/www -V file://${PWD}/update/www \
    -f ${format} -l ister.log -S ${tempdir}

sudo -E rm -rf ${tempdir}

mkdir -p releases
sudo -E mv release.img releases/${DSTREAM_NAME}-${MIX_VERSION}-kvm.img

popd > /dev/null
