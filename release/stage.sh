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

# MIX_VERSION:  Version number for this new Mix being generated

set -e

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))

. ${SCRIPT_DIR}/../common.sh

test_dir ${STAGING_DIR}
test_dir ${BUILD_DIR}

pushd ${BUILD_DIR} > /dev/null

echo "Staging Mix ..."
/usr/bin/mkdir -p ${STAGING_DIR}/update/
/usr/bin/cp -a update/www/* ${STAGING_DIR}/update/

echo "Setting latest version ..."
/usr/bin/cp -a update/latest ${STAGING_DIR}/

echo "Staging release image ..."
/usr/bin/cp -a releases ${STAGING_DIR}/

echo "Fixing permissions and ownership ..."
sudo -E /usr/bin/chown -R ${USER}:httpd ${STAGING_DIR}

popd > /dev/null
