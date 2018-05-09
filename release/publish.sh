#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))

. ${SCRIPT_DIR}/../common.sh
. ./config/config.sh

REMOTE_PATH=${PUBLISHING_HOST}:${PUBLISHING_ROOT}/${NAMESPACE:-${DSTREAM_NAME}}

cat <<EOL
=== PUBLISH
From:
    ${STAGING_DIR}
To:
    ${REMOTE_PATH}

== Syncing Content ==

EOL

assert_dir ${STAGING_DIR}
rsync -vrlHpt --delete --exclude '*.src.rpm' -e ssh ${STAGING_DIR}/ ${REMOTE_PATH}
