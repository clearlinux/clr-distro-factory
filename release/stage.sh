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

assert_dir ${STAGING_DIR}
assert_dir ${BUILD_DIR}
assert_dir ${BUILD_DIR}/git-bundles #FIXME Mixer 4.3.3 workaround
assert_dir ${BUILD_DIR}/local-bundles

var_load MIX_VERSION

pushd ${BUILD_DIR} > /dev/null

echo "=== STAGING MIX"
mkdir -p ${STAGING_DIR}/update/
rsync -ah update/www/ ${STAGING_DIR}/update/

echo "== SETTING LATEST VERSION =="
/usr/bin/cp -a update/latest ${STAGING_DIR}/

mkdir -p ${STAGING_DIR}/releases/
rsync -ah releases/ ${STAGING_DIR}/releases/

popd > /dev/null

cp -a ${BUILD_FILE} ${STAGING_DIR}/releases/${BUILD_FILE}-${MIX_VERSION}.txt
cp -a ${PKG_LIST_FILE} ${STAGING_DIR}/releases/${PKG_LIST_FILE}-${MIX_VERSION}.txt
cp -a ${RELEASE_NOTES} ${STAGING_DIR}/releases/${RELEASE_NOTES}-${MIX_VERSION}.txt

echo "== FIXING PERMISSIONS AND OWNERSHIP =="
sudo -E /usr/bin/chown -R ${USER}:httpd ${STAGING_DIR}

echo "== TAGGING =="
echo "Workflow Configuration:"
git -C config tag -f ${MIX_VERSION}
git -C config push --quiet -f --tags origin
echo "    Tag: ${MIX_VERSION}. OK!"

mv -f ${BUILD_DIR}/git-bundles ${BUILD_DIR}/local-bundles/.git
echo "Downstream Bundles Repository:"
git -C ${BUILD_DIR}/local-bundles tag -f ${NAMESPACE:-${DSTREAM_NAME}}-${MIX_VERSION}
git -C ${BUILD_DIR}/local-bundles push --quiet -f --tags origin
echo "    Tag: ${NAMESPACE:-${DSTREAM_NAME}}-${MIX_VERSION}. OK!"
