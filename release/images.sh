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
. ${SCRIPT_DIR}/../config/config.sh

var_load MIX_VERSION

LOG_DIR="${WORK_DIR}/logs"
PROCS_PER_IMG=8
TEMPLATES_PATH=${TEMPLATES_PATH:-"${PWD}/config/images"}

create_image() {
    # ${1} - File path to image template file
    local image=${1}
    local tempdir=$(mktemp -d)
    local name=$(basename ${image%.json})
    local ister_log="${LOG_DIR}/ister-${name}.log"

    if [[ -z "${image}" || -z "${name}" ]]; then
        error "Image creation failed. Invalid input" "${1}"
        return 1
    fi

    pushd ${BUILD_DIR} > /dev/null
    sudo -E ister.py -s Swupd_Root.pem -L debug -S ${tempdir} \
        -C file://${BUILD_DIR}/update/www -V file://${BUILD_DIR}/update/www \
        -f ${format} -t ${image} > ${ister_log} 2>&1
    local ister_ret=$?
    sudo rm -rf ${tempdir}

    if (( ${ister_ret} )) || [[ ! -s "${name}.img" ]]; then
        log "Image '${name}'" "Failed. See log below:"
        echo
        cat ${ister_log}
        echo
        return 1
    fi

    xz -3 --stdout ${name}.img > releases/${DSTREAM_NAME}-${MIX_VERSION}-${name}.img.xz
    sudo rm ${name}.img

    if [[ ! -s "releases/${DSTREAM_NAME}-${MIX_VERSION}-${name}.img.xz" ]]; then
        log "Image '${name}'" "Failed to create compressed file."
        return 1
    fi

    popd > /dev/null
    log "Image '${name}'" "OK!"
}

parallel_fn() {
    # Intended to be used only by GNU Parallel
    . ${SCRIPT_DIR}/../globals.sh
    . ${SCRIPT_DIR}/../common.sh
    . ${SCRIPT_DIR}/../config/config.sh

    create_image $@
}

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

mkdir -p ${LOG_DIR}
mkdir -p ${BUILD_DIR}/releases

export LOG_DIR
export MIX_VERSION
export SCRIPT_DIR
export -f create_image
export -f parallel_fn
export format
procs=$(nproc --all)
max_jobs=$(( ${procs:=0} > ${PROCS_PER_IMG} ? ${procs} / ${PROCS_PER_IMG} : 1 ))
parallel -j ${max_jobs} parallel_fn <<< ${image_list}
