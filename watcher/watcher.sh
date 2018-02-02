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

CLR_LATEST=$(curl ${CLR_PUBLIC_DL_URL}/latest 2> /dev/null)
if [ -z $CLR_LATEST ]; then
    echo "Error: Failed to fetch Clear Linux latest version."
    exit 1
fi

DS_LATEST=$(curl ${DSTREAM_DL_URL}/latest 2> /dev/null)
if [ -z $DS_LATEST ]; then
    echo "Error: Failed to fetch Downstream Clear Linux latest version."
    exit 1
elif ((${#DS_LATEST} < 4)); then
    echo "Error: Downstream Clear Linux version number seems corrupted."
    exit 1
fi

DS_UP_VERSION=${DS_LATEST: : -3}
DS_DOWN_VERSION=${DS_LATEST: -3}

echo "Downstream version:  $DS_UP_VERSION $DS_DOWN_VERSION"
echo "Clear Linux version: $CLR_LATEST"

if (($DS_UP_VERSION < $CLR_LATEST)); then
    echo "It's Release Time!"
else
    echo "No Release for you!"
fi
