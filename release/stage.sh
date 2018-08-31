#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))

. ${SCRIPT_DIR}/../globals.sh
. ${SCRIPT_DIR}/../common.sh

. ./config/config.sh

var_load MIX_VERSION

RELEASE_DIR="${WORK_DIR}/release"

stage "Staging Release"

assert_dir ${BUILD_DIR}/local-bundles
assert_dir ${RELEASE_DIR}
assert_dir ${STAGING_DIR}

log_line "Finishing 'release' folder"
mv ${WORK_DIR}/${BUILD_FILE} ${RELEASE_DIR}/${BUILD_FILE}-${MIX_VERSION}.txt
mv ${WORK_DIR}/${PKG_LIST_FILE} ${RELEASE_DIR}/${PKG_LIST_FILE}-${MIX_VERSION}.txt
mv ${WORK_DIR}/${RELEASE_NOTES} ${RELEASE_DIR}/${RELEASE_NOTES}-${MIX_VERSION}.txt
cp -a ${BUILD_DIR}/Swupd_Root.pem ${RELEASE_DIR}/config/
log_line "OK!" 1

log_line "Staging 'update'"
mkdir -p ${STAGING_DIR}/update/
rsync -ah ${BUILD_DIR}/update/www/ ${STAGING_DIR}/update/
log_line "OK!" 1

log_line "Staging 'release'"
mkdir -p ${STAGING_DIR}/releases/${MIX_VERSION}
rsync -ah ${RELEASE_DIR}/ ${STAGING_DIR}/releases/${MIX_VERSION}/
log_line "OK!" 1

pushd ${STAGING_DIR} > /dev/null
log_line "Updating 'latest' pointers"
cp -a ${BUILD_DIR}/update/latest ./
ln -sfT ./${MIX_VERSION} ./update/latest
ln -sfT ./${MIX_VERSION} ./releases/latest
ln -sfT ./releases/${MIX_VERSION}/images ./images
popd > /dev/null
log_line "OK!" 1

log_line "Fixing permissions and ownership"
sudo -E /usr/bin/chown -R ${USER}:httpd ${STAGING_DIR}
log_line "OK!" 1

section "Tagging Repositories"
log_line "Workflow Configuration:"
git -C config tag -f ${MIX_VERSION}
git -C config push --quiet -f --tags origin
log_line "Tag: ${MIX_VERSION}. OK!" 1

log_line "Downstream Bundles Repository:"
git -C ${BUILD_DIR}/local-bundles tag -f ${NAMESPACE:-${DSTREAM_NAME}}-${MIX_VERSION}
git -C ${BUILD_DIR}/local-bundles push --quiet -f --tags origin
log_line "Tag: ${NAMESPACE:-${DSTREAM_NAME}}-${MIX_VERSION}. OK!" 1
