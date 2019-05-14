#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=globals.sh
# shellcheck source=common.sh

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../globals.sh"
. "${SCRIPT_DIR}/../common.sh"

. ./config/config.sh

var_load MIX_VERSION

bundles_dir="${BUILD_DIR}/local-bundles"
release_dir="${WORK_DIR}/release"
bundles_tag="${NAMESPACE:-${DSTREAM_NAME}}-${MIX_VERSION}"

# ==============================================================================
# MAIN
# ==============================================================================
stage "Staging Release"

assert_dir "${REPO_DIR}"
assert_dir "${STAGING_DIR}"

assert_dir "${bundles_dir}"
assert_dir "${release_dir}"

section "Copying Artifacts"
log_line "Finishing 'release' folder"
mv "${WORK_DIR}/${BUILD_FILE}" "${release_dir}/${BUILD_FILE}-${MIX_VERSION}.txt"
mv "${WORK_DIR}/${PKG_LIST_FILE}" "${release_dir}/${PKG_LIST_FILE}-${MIX_VERSION}.txt"
mv "${WORK_DIR}/${RELEASE_NOTES}" "${release_dir}/${RELEASE_NOTES}-${MIX_VERSION}.txt"
mv "${WORK_DIR}/${MCA_FILE}-"*.txt "${release_dir}/" || true # prevents failure when no MCA logs exist.

mv "${REPO_DIR}/" "${release_dir}/repo/"
cp -a "${BUILD_DIR}/Swupd_Root.pem" "${release_dir}/config/"
git -C "${bundles_dir}" archive --format='tar.gz' --prefix='bundles/' \
    -o "${release_dir}/${BUNDLES_FILE}-${MIX_VERSION}.tar.gz" HEAD > /dev/null 2>&1
tar xf "${release_dir}/${BUNDLES_FILE}-${MIX_VERSION}.tar.gz" -C "${release_dir}/config/"
if [[ -d "${SCRIPT_DIR}/../config/images" ]]; then
    cp -a "${SCRIPT_DIR}/../config/images" "${release_dir}/config/"
fi
log_line "OK!" 1

log_line "Staging 'update'"
mkdir -p "${STAGING_DIR}/update/"
rsync -ah "${BUILD_DIR}/update/www/" "${STAGING_DIR}/update/"
log_line "OK!" 1

log_line "Staging 'release'"
mkdir -p "${STAGING_DIR}/releases/${MIX_VERSION}"
rsync -ah "${release_dir}/" "${STAGING_DIR}/releases/${MIX_VERSION}/"
log_line "OK!" 1

pushd "${STAGING_DIR}" > /dev/null
log_line "Updating 'latest' pointers"
cp -a "${BUILD_DIR}/update/latest" ./
ln -sfT "./${MIX_VERSION}" ./update/latest
ln -sfT "./${MIX_VERSION}" ./releases/latest
ln -sfT "./releases/${MIX_VERSION}/images" ./images
popd > /dev/null
log_line "OK!" 1

log_line "Fixing permissions and ownership"
sudo -E /usr/bin/chown -R "${USER}:httpd" "${STAGING_DIR}"
log_line "OK!" 1

section "Tagging Repositories"
log_line "Workflow Configuration:"
git -C config tag -f "${MIX_VERSION}"
git -C config push --quiet -f --tags origin
log_line "Tag: ${MIX_VERSION}. OK!" 1

log_line "Downstream Bundles Repository:"
git -C "${bundles_dir}" tag -f "${bundles_tag}"
git -C "${bundles_dir}" push --quiet -f --tags origin
log_line "Tag: ${bundles_tag}. OK!" 1
