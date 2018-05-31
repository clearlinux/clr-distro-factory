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

TEMPLATES_PATH=${TEMPLATES_PATH:-"${PWD}/config/images"}

# ==============================================================================
# MAIN
# ==============================================================================
stage "Image Generation"

image_list=$(ls ${TEMPLATES_PATH}/*.json 2>/dev/null || true)
if [[ -z "${image_list}" ]]; then
    warn "Skipping stage."
    warn "No image definition files found in" "${TEMPLATES_PATH}"
    exit 0
fi

format=$(< ${BUILD_DIR}/update/www/${MIX_VERSION}/format)
if [[ -z "${format}" ]]; then
    error "Failed to fetch Downstream current format."
    exit 1
fi

pushd ${BUILD_DIR} > /dev/null
mkdir -p releases

log_line "Creating Images:"

LOG_INDENT=1
for image in ${image_list}; do
    tempdir=$(mktemp -d)
    name=$(basename ${image%.json})

    log_line "${name}:"
    sudo -E ister.py -s Swupd_Root.pem -L debug -S ${tempdir} \
        -C file://${BUILD_DIR}/update/www -V file://${BUILD_DIR}/update/www \
        -f ${format} -t ${image} -l ister-${name}.log

    xz -3 --stdout ${name}.img > releases/${DSTREAM_NAME}-${MIX_VERSION}-${name}.img.xz
    log_line "OK!" 1

    sudo rm ${name}.img
    sudo rm -rf ${tempdir}
done
unset LOG_INDENT

popd > /dev/null
