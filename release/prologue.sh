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

. ${SCRIPT_DIR}/../common.sh

cat <<EOL
=== PROLOGUE
Workflow Repository:
    $(git remote get-url origin) ($(git rev-parse --short HEAD))
EOL
fetch_config_repo
. ./config/config.sh

cat <<EOL
== Configuration ==
Downstream:
    ${DSTREAM_NAME}
Bundles Repository:
    ${BUNDLES_REPO}
Downstream Content/Version URL:
    ${DSTREAM_DL_URL}
Downstream Koji Server:
    ${KOJI_URL}
Downstream Koji Tag:
    ${KOJI_TAG}

== Workspace ==
Namespace:
    ${NAMESPACE}
Work dir:
    ${WORK_DIR}
Variables dir:
    ${VARS_DIR}
Build dir:
    ${BUILD_DIR}
Stage dir:
    ${STAGING_DIR}

EOL

echo -n "Sanitizing work environment..."
mkdir -p ${BUILD_DIR}
mkdir -p ${STAGING_DIR}
echo "OK!"
echo "==="
