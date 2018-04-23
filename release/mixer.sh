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
#
# MIX_LATEST_VERSION:       Latest, already staged, version of this Mix
# MIX_LATEST_FORMAT:        Latest, already staged, format  of this Mix
#
# UPSTREAM_URL:             The Upstream Software Update URL this Mix is based upon
#
# UPSTREAM_BASE_VERSION:    Version of the upstream to use as base for this Mix
# UPSTREAM_BASE_FORMAT:     Format  of the upstream to use as base for this Mix
#
# UPSTREAM_PREV_VERSION:    Version of the upstream used by the Previous Mix
# UPSTREAM_PREV_FORMAT:     Format  of the upstream used by the Previous Mix
#
# CLR_BUNDLES: Subset of bundles to be used from upstream (instead of all)

set -e

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))

. ${SCRIPT_DIR}/../globals.sh
. ${SCRIPT_DIR}/../common.sh

. ./config/config.sh

BUILDER_CONF=${BUILDER_CONF:-"${BUILD_DIR}/builder.conf"}
MIX_INCREMENT=${MIX_INCREMENT:-10}

UPSTREAM_URL=${UPSTREAM_URL:-"${CLR_PUBLIC_DL_URL}/update/"}

echo "=== MIXER STEP STARTING"
echo
echo "BUILDER_CONF=${BUILDER_CONF}"
echo "MIX_INCREMENT=${MIX_INCREMENT}"
echo "MIX_BUNDLES_URL=${MIX_BUNDLES_URL}"
echo "UPSTREAM_URL=${UPSTREAM_URL}"
echo "CLR_BUNDLES=${CLR_BUNDLES:-"all from upstream"}"
echo "KOJI_TOPURL=${KOJI_TOPURL}"
echo "KOJI_TAG=${KOJI_TAG}"

get_latest_versions() {
    echo
    echo "=== GET LATEST VERSIONS"

    {
        # Should we allow this to be set via an Environment variable???
        MIX_LATEST_VERSION=${MIX_LATEST_VERSION:-$(curl file://${STAGING_DIR}/latest)}
    } || {
        MIX_LATEST_VERSION=""
    }

    {
        UPSTREAM_BASE_VERSION=${UPSTREAM_BASE_VERSION:-$(curl ${UPSTREAM_URL}../latest)} &&
        UPSTREAM_BASE_FORMAT=$(curl ${UPSTREAM_URL}${UPSTREAM_BASE_VERSION}/format)
    } || {
        echo "Failed to get ClearLinux upstream latest version information!"
        exit 4
    }

    if [ -z ${MIX_LATEST_VERSION} ]; then
        MIX_VERSION=${MIX_VERSION:-$(( ${UPSTREAM_BASE_VERSION} * 1000 + ${MIX_INCREMENT}))}

        MIX_LATEST_VERSION=${MIX_VERSION}
        MIX_LATEST_FORMAT=0

        UPSTREAM_PREV_VERSION=${UPSTREAM_BASE_VERSION}
        UPSTREAM_PREV_FORMAT=${UPSTREAM_BASE_FORMAT}
    else
        { # Get Latest Mix version's format (we already have the version)
            MIX_LATEST_FORMAT=$(curl file://${STAGING_DIR}/update/${MIX_LATEST_VERSION}/format)
        } || { # Failed
            echo "Failed to get latest mix format!"
            exit 2
        }

        UPSTREAM_PREV_VERSION=${MIX_LATEST_VERSION::-3}

        { # Get the Upstream version and format for the previous mix
            UPSTREAM_PREV_FORMAT=$(curl ${UPSTREAM_URL}${UPSTREAM_PREV_VERSION}/format)
        } || { # Failed
            echo "Failed to get Upstream previous ClearLinux version information!"
            exit 2
        }

        if [ ${UPSTREAM_BASE_VERSION} -lt ${UPSTREAM_PREV_VERSION} ]; then
            echo "Invalid Mix version: Specified Upstream Base less than the previous Upstream!"
            echo "Abort..."
            exit 1
        fi

        MIX_VERSION=${MIX_VERSION:-$(( ${UPSTREAM_BASE_VERSION} * 1000 + ${MIX_INCREMENT}))}

        if [ ${MIX_VERSION} -le ${MIX_LATEST_VERSION} ]; then
            MIX_VERSION=$(( ${MIX_LATEST_VERSION} + ${MIX_INCREMENT} ))

            if [ "${MIX_VERSION:(-3)}" -eq "000" ]; then
                echo "Invalid Mix version: no more versions available for mix for this upstream!"
                echo "Abort..."
                exit 1
            fi

            if [ ${MIX_VERSION} -le ${MIX_LATEST_VERSION} ]; then
                echo "Invalid Mix version ${MIX_VERSION} with the latest being ${MIX_LATEST_VERSION}!"
                echo "Abort..."
                exit 1
            fi
        fi
    fi

    if [ "${MIX_VERSION}" -eq "${MIX_LATEST_VERSION}" ]; then
        echo "This is the first version of this mix!"
    else
        echo "Latest Downstream Version: ${MIX_LATEST_VERSION}:${MIX_LATEST_FORMAT}"
        echo "Based on Upstream Version: ${UPSTREAM_PREV_VERSION}:${UPSTREAM_PREV_FORMAT}"
    fi
    echo     "Latest Upstream Version:   ${UPSTREAM_BASE_VERSION}:${UPSTREAM_BASE_FORMAT}"
    echo     "Next Downstream Version:   ${MIX_VERSION}"
}

download_bundles() {
    local clear_ver="$1"
    local mix_ver="$2"

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
    /usr/bin/git clone --quiet ${MIX_BUNDLES_URL} ${MIX_DIR}

    # Ensure the Upstream and Mix versions are set
    if [ -f "${BUILDER_CONF}/mixversion" ]; then
        # Update the Clear and Mix versions
        echo -n ${clear_ver} | sudo -E \
            tee "$BUILD_DIR/upstreamversion" > /dev/null
        echo -n ${mix_ver} | sudo -E \
            tee "$BUILD_DIR/mixversion" > /dev/null
    else
        # We have no mixversion, so we need to call init-mix for the first (and only) time
        sudo -E mixer init --config ${BUILDER_CONF} --clear-version ${clear_ver} --mix-version ${mix_ver}
    fi

    # Add the upstream Bundle definitions for this base version of ClearLinux
    sudo -E mixer bundle add --config ${BUILDER_CONF} ${CLR_BUNDLES:-"--all-upstream"}

    # Clean up
    sudo -E /usr/bin/rm -rf clr-bundles

    # Ensure our custom bundles replace any upstream files
    pushd ${MIX_DIR} > /dev/null
    /usr/bin/git reset --quiet --hard HEAD
    # Change back to previous working directory
    popd > /dev/null
}

download_mix_rpms() {
    echo ""
    echo "=== FETCHING CUSTOM PKG LIST"
    local result=$(koji_cmd list-tagged --latest --quiet ${KOJI_TAG}) \
        || { echo "Failed to get Mix packages!"; exit 2; }
    echo "${result}" | awk '{print $1}' > ${PKG_LIST_FILE}
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

    download_bundles "${clear_ver}" "${mix_ver}"

    echo
    echo "=== GENERATING MIX"

    # Create the local repo directory
    LOCAL_REPO=$(grep '^LOCAL_REPO_DIR' ${BUILDER_CONF} | awk -F= '{print $NF}')
    # Expand the environment variables
    LOCAL_REPO=$(echo $(eval echo ${LOCAL_REPO}))
    /usr/bin/mkdir -p ${LOCAL_REPO}

    echo ""
    echo "Adding RPMs ..."
    sudo -E mixer add-rpms --config ${BUILDER_CONF}

    echo ""
    echo "Creating chroots ..."
    sudo -E mixer build bundles --config ${BUILDER_CONF}

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
    sudo -E mixer build update --config ${BUILDER_CONF}

    if [ "${MIX_LATEST_VERSION}" -lt "${mix_ver}" ]; then
        echo ""
        echo "Generating upgrade packs ..."
        sudo -E mixer-pack-maker.sh --to ${mix_ver} --from ${MIX_LATEST_VERSION} -S ${BUILD_DIR}/update
    fi

    echo -n ${mix_ver} | sudo -E tee update/latest > /dev/null
    sudo -E /usr/bin/cp -a ${PKG_LIST_FILE} update/www/${mix_ver}/
}

main() {
    assert_dir ${BUILD_DIR}
    pushd ${BUILD_DIR} > /dev/null

    if [ -f ${BUILDER_CONF} ]; then
        echo
        echo "=== USING EXISTING BUILDER.CONF FILE"
    else
        echo
        echo "=== GENERATE BUILDER.CONF FILE"

        # Write the configuration file based on the template.
        sed -e "s#\${BUILD_DIR}#${BUILD_DIR}#" -e "s#\${DSTREAM_DL_URL}#${DSTREAM_DL_URL}#" ${SCRIPT_DIR}/builder.conf.in > ${BUILDER_CONF}
    fi

    echo "${BUILDER_CONF} contents:"
    cat ${BUILDER_CONF}

    get_latest_versions

    download_mix_rpms # Pull down the RPMs from Downstream Koji

    if [ "${UPSTREAM_BASE_FORMAT}" -gt "${UPSTREAM_PREV_FORMAT}" ]; then
        echo "=== NEED TO BUMP FORMAT"
    fi

    local format_bumps=$(( ${UPSTREAM_BASE_FORMAT} - ${UPSTREAM_PREV_FORMAT} ))
    for (( bump=0 ; bump < ${format_bumps} ; bump++ )); do
        local up_prev_format=$(( ${UPSTREAM_PREV_FORMAT} + ${bump}))
        local up_prev_latest_ver
        local up_next_first_ver

        # First, we may need to generate a Mix based on the latest upstream
        # release for the previous upstream Format.
        { # Get the latest version for Upstream format
            up_prev_latest_ver=$(curl --silent --fail ${UPSTREAM_URL}version/format${up_prev_format}/latest)
        } || { # Failed
            echo "Failed to get latest version for Upstream format ${up_prev_format}!"
            exit 2
        }

        local step_mix_ver
        if [ "${UPSTREAM_PREV_VERSION}" -lt "${up_prev_latest_ver}" ]; then
            step_mix_ver=$(( ${up_prev_latest_ver} * 1000 + ${MIX_INCREMENT} ))
        else
            # We some built a Mix based on the last version of a format, without bumping
            step_mix_ver=$(( ${up_prev_latest_ver} * 1000 + ${MIX_INCREMENT} + ${MIX_INCREMENT} ))
        fi

        local next_mix_format=$(( ${MIX_LATEST_FORMAT} + 1 ))
        { # Get the first version for Upstream next format
            local up_next_format=$(( ${up_prev_format} + 1 ))
            up_next_first_ver=$(curl --silent --fail ${UPSTREAM_URL}version/format${up_next_format}/first)
        } || { # Failed
            echo "Failed to get first version for Upstream format ${up_next_format}!"
            exit 2
        }
        local next_mix_ver=$(( ${up_next_first_ver} * 1000 + ${MIX_INCREMENT} ))

        # Generate a Mix based on the FIRST release for the new Format
        echo
        echo "=== GENERATING INTERMEDIATE MIX ${step_mix_ver}"
        generate_mix "${up_prev_latest_ver}" "${step_mix_ver}" ${next_mix_format} ${next_mix_ver}

        # Bump the Mix Format
        # Modify the BUILDER_CONF with the new format
        # TODO: Need to check-in to git
        sed -r 's/^(FORMAT=)([0-9]+)(.*)/echo "\1$((\2+1))\3"/ge' ${BUILDER_CONF} > ${BUILDER_CONF}.new
        mv ${BUILDER_CONF}.new ${BUILDER_CONF}

        echo
        echo "=== GENERATING INTERMEDIATE MIX ${next_mix_ver}"
        generate_mix "${up_next_first_ver}" "${next_mix_ver}"
    done

    generate_mix "${UPSTREAM_BASE_VERSION}" "${MIX_VERSION}"

    popd > /dev/null
}

main
