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

# MIX_VERSION: Version number for this new Mix being generated
# CLR_BUNDLES: Subset of bundles to be used from upstream (instead of all)

set -e

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))

. ${SCRIPT_DIR}/../globals.sh
. ${SCRIPT_DIR}/../common.sh

. ./config/config.sh

var_load CLR_FORMAT
var_load CLR_LATEST
var_load DS_DOWN_VERSION
var_load DS_FORMAT
var_load DS_LATEST
var_load DS_UP_FORMAT
var_load DS_UP_VERSION
var_load MIX_VERSION
var_load MIX_UP_VERSION
var_load MIX_DOWN_VERSION

download_bundles() {
    echo ""
    echo "=== DOWNLOADING BUNDLES"

    if [ -z ${MIX_DIR} ]; then
        MIX_DIR="mix-bundles"
    fi

    if [ -d ${MIX_DIR} ]; then
        # Rename any existing MIX directory
        /usr/bin/mv ${MIX_DIR} ${MIX_DIR}.$(date +%Y%m%d.%H%M%S)
    fi

    # Clone the Mix Bundles repo
    /usr/bin/git clone --quiet ${BUNDLES_REPO} ${MIX_DIR}

    # Ensure our custom bundles replace any upstream files
    pushd ${MIX_DIR} > /dev/null
    /usr/bin/git reset --quiet --hard HEAD
    # Change back to previous working directory
    popd > /dev/null
}

download_mix_rpms() {
    echo ""
    echo "=== FETCHING CUSTOM PKG LIST"
    local result
    if result=$(koji_cmd list-tagged --latest --quiet ${KOJI_TAG}); then
        echo "${result}" | awk '{print $1}' > ${PKG_LIST_FILE}
    else
        echo "[ERROR] Failed to get Mix packages!"
        exit 2
    fi
    cat ${PKG_LIST_FILE}

    echo ""
    echo "=== DOWNLOADING RPMS"

    if [ -z ${RPM_DIR} ]; then
        RPM_DIR="rpms"
    fi

    # Remove any existing RPM directory as it may contain
    # RPMs which are no longer tagged from a previous download
    if [ -d ${RPM_DIR} ]; then
        /usr/bin/rm -rf ${RPM_DIR}
    fi
    # Create and change to RPM target directory
    /usr/bin/mkdir -p ${RPM_DIR}
    pushd ${RPM_DIR} > /dev/null

    for rpm in $(cat ${BUILD_DIR}/${PKG_LIST_FILE}); do
        echo "--- ${rpm}"
        koji_cmd download-build -a x86_64 --quiet ${rpm}
    done

    # Change back to previous working directory
    popd > /dev/null
}

generate_mix() {
    local clear_ver="$1"
    local mix_ver="$2"
    local bump_format=$(( "$3" + 0 ))
    local bump_ver=$(( "$4" + 0 ))

    echo
    echo "=== GENERATING MIX"

    # Clean bundles file, otherwise mixer will use the outdated list
    # and cause an error if bundles happen to be deleted
    rm -f ./mixbundles

    # Ensure the Upstream and Mix versions are set
    sudo -E mixer init --clear-version ${clear_ver} --mix-version ${mix_ver}

    # Add the upstream Bundle definitions for this base version of ClearLinux
    sudo -E mixer bundle add ${CLR_BUNDLES:-"--all-upstream"}

    download_bundles

    # Create the local repo directory
    LOCAL_REPO=$(grep '^LOCAL_REPO_DIR' ${BUILD_DIR}/builder.conf | awk -F= '{print $NF}')
    # Expand the environment variables
    LOCAL_REPO=$(echo $(eval echo ${LOCAL_REPO}))
    /usr/bin/mkdir -p ${LOCAL_REPO}

    echo ""
    echo "Adding RPMs ..."
    sudo -E mixer add-rpms

    echo ""
    echo "Creating chroots ..."
    sudo -E mixer build bundles

    if [[ "${bump_format}" -gt 0 ]]; then
        echo ""
        echo "*** BUMP: Forcing the image version ahead to ${bump_ver}:${bump_format} ..."
        echo -n ${bump_format} | sudo -E \
            tee "$BUILD_DIR/update/image/${mix_ver}/full/usr/share/defaults/swupd/format" > /dev/null
        echo -n ${bump_ver} | sudo -E \
            tee "$BUILD_DIR/update/image/${mix_ver}/full/usr/share/clear/version" > /dev/null
    fi

    echo ""
    echo "Building update ..."
    sudo -E mixer build update

    if [[ -n "${DS_LATEST}" ]]; then
        echo ""
        echo "Generating upgrade packs ..."
        sudo -E mixer-pack-maker.sh --to ${mix_ver} --from ${DS_LATEST} -S ${BUILD_DIR}/update
    fi

    echo -n ${mix_ver} | sudo -E tee update/latest > /dev/null
    sudo -E /usr/bin/cp -a ${PKG_LIST_FILE} update/www/${mix_ver}/
}

# ==============================================================================
# MAIN
# ==============================================================================
echo "=== STARTING MIXING"
echo
echo "MIX_INCREMENT=${MIX_INCREMENT}"
echo "CLR_BUNDLES=${CLR_BUNDLES:-"all from upstream"}"

assert_dir ${BUILD_DIR}
pushd ${BUILD_DIR} > /dev/null

echo
echo "Builder Conf file:"
if [[ -f ${BUILD_DIR}/builder.conf ]]; then
    echo "    Reusing existing file"
else
    echo "    Generating new file"

    # Write the configuration file based on the template.
    sed -e "s#\${BUILD_DIR}#${BUILD_DIR}#" \
        -e "s#\${DSTREAM_DL_URL}#${DSTREAM_DL_URL}#" \
        ${SCRIPT_DIR}/builder.conf.in > ${BUILD_DIR}/builder.conf
fi
echo "Builder Conf Contents:"
cat ${BUILD_DIR}/builder.conf

download_mix_rpms # Pull down the RPMs from Downstream Koji

if [[ -z ${DS_LATEST} ]]; then
    # This is our First Mix!
    DS_UP_FORMAT=${CLR_FORMAT}
    DS_UP_VERSION=${CLR_LATEST}
fi

format_bumps=$(( ${CLR_FORMAT} - ${DS_UP_FORMAT} ))
if (( ${format_bumps} )); then
    echo "=== NEED TO BUMP FORMAT"
fi
for (( bump=0 ; bump < ${format_bumps} ; bump++ )); do
    up_prev_format=$(( ${DS_UP_FORMAT} + ${bump}))
    declare up_prev_latest_ver
    declare up_next_first_ver

    # First, we may need to generate a Mix based on the latest upstream
    # release for the previous upstream Format.
    { # Get the latest version for Upstream format
        up_prev_latest_ver=$(curl --silent --fail ${CLR_PUBLIC_DL_URL}/update/version/format${up_prev_format}/latest)
    } || { # Failed
        echo "Failed to get latest version for Upstream format ${up_prev_format}!"
        exit 2
    }

    declare step_mix_ver
    if [ "${DS_UP_VERSION}" -lt "${up_prev_latest_ver}" ]; then
        step_mix_ver=$(( ${up_prev_latest_ver} * 1000 + ${MIX_INCREMENT} ))
    else
        # We built a Mix based on the last version of a format, without bumping
        step_mix_ver=$(( ${up_prev_latest_ver} * 1000 + ${MIX_INCREMENT} + ${MIX_INCREMENT} ))
    fi

    next_mix_format=$(( ${DS_FORMAT} + 1 ))
    { # Get the first version for Upstream next format
        up_next_format=$(( ${up_prev_format} + 1 ))
        up_next_first_ver=$(curl --silent --fail ${CLR_PUBLIC_DL_URL}/update/version/format${up_next_format}/first)
    } || { # Failed
        echo "Failed to get first version for Upstream format ${up_next_format}!"
        exit 2
    }
    next_mix_ver=$(( ${up_next_first_ver} * 1000 + ${MIX_INCREMENT} ))

    # Generate a Mix based on the FIRST release for the new Format
    echo
    echo "=== GENERATING INTERMEDIATE MIX ${step_mix_ver}"
    generate_mix "${up_prev_latest_ver}" "${step_mix_ver}" ${next_mix_format} ${next_mix_ver}

    # Bump the Mix Format
    # Modify the "builder.conf" with the new format
    # TODO: Need to check-in to git
    # TODO: Sed in place
    sed -r 's/^(FORMAT=)([0-9]+)(.*)/echo "\1$((\2+1))\3"/ge' ${BUILD_DIR}/builder.conf > ${BUILD_DIR}/builder.conf.new
    mv ${BUILD_DIR}/builder.conf.new ${BUILD_DIR}/builder.conf

    echo
    echo "=== GENERATING INTERMEDIATE MIX ${next_mix_ver}"
    generate_mix "${up_next_first_ver}" "${next_mix_ver}"
done

generate_mix "${CLR_LATEST}" "${MIX_VERSION}"

popd > /dev/null
