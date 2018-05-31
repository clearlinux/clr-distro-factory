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

BUILDER_CONF=${BUILDER_CONF:-"${BUILD_DIR}/builder.conf"}
IMAGE_TEMPLATE=${IMAGE_TEMPLATE:-"${PWD}/config/release-image-config.json"}

main() {
    assert_dir ${BUILD_DIR}
    pushd ${BUILD_DIR} > /dev/null

    echo "${IMAGE_TEMPLATE} contents:"
    cat ${IMAGE_TEMPLATE}

    echo
    echo "=== GENERATING RELEASE IMAGE"
    local tempdir=$(mktemp -d)
    CURRENT_FORMAT=$(grep '^FORMAT' ${BUILDER_CONF} | awk -F= '{print $NF}')

    sudo -E ister.py -s Swupd_Root.pem -t ${IMAGE_TEMPLATE} \
        -C file://${PWD}/update/www -V file://${PWD}/update/www \
        -f ${CURRENT_FORMAT} -l ister.log -S ${tempdir}

    sudo -E rm -rf ${tempdir}

    mix_version=$(cat mixversion)
    mkdir -p releases
    sudo -E /usr/bin/mv release.img releases/${DSTREAM_NAME}-${mix_version}-kvm.img

    popd > /dev/null
}

main
