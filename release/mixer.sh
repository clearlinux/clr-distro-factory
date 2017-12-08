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

# MIX_LATEST_VERSION:       Latest, already staged, version of this Mix
# MIX_LATEST_FORMAT:        Latest, already staged, format  of this Mix

# UPSTREAM_URL:             The Upstream Software Update URL this Mix is based upon

# UPSTREAM_BASE_VERSION:    Version of the upstream to use as base for this Mix
# UPSTREAM_BASE_FORMAT:     Format  of the upstream to use as base for this Mix

# UPSTREAM_PREV_VERSION:    Version of the upstream used by the Previous Mix
# UPSTREAM_PREV_FORMAT:     Format  of the upstream used by the Previous Mix

set -e

SCRIPT_DIR=$(dirname $(realpath ${BASH_SOURCE[0]}))

. ${SCRIPT_DIR}/../globals.sh
. ${SCRIPT_DIR}/../common.sh

BUILDER_CONF=${BUILDER_CONF:-"${BUILD_DIR}/builder.conf"}
MIX_INCREMENT=${MIX_INCREMENT:-10}
MIX_BUNDLES_URL=${MIX_BUNDLES_URL:?"Downstream Bundles Repository is required"}

UPSTREAM_URL=${UPSTREAM_URL:-"${CLR_PUBLIC_DL_URL}/update/"}

# Comma (no whitespace) separated list of bundles to include
# Leave zero length string for all ClearLinux bundles (Default mode)
INC_BUNDLES=${INC_BUNDLES:-"bootloader,kernel-native,os-core,os-core-update"}

# URL of RPM download site
KOJI_TOPURL=${KOJI_TOPURL:?"Downstream Koji Top URL is required"}
KOJI_RPM_TAG=${KOJI_RPM_TAG:-"dist-ds"} # Koji tag of RPMs to use

get_latest_versions() {
    {
        # Should we allow this to be set via an Environment variable???
        MIX_LATEST_VERSION=${MIX_LATEST_VERSION:-$(curl --silent --fail file://${STAGING_DIR}/latest)}
    } || {
        MIX_LATEST_VERSION=""
    }

    {
        UPSTREAM_BASE_VERSION=${UPSTREAM_BASE_VERSION:-$(curl --silent --fail ${UPSTREAM_URL}../latest)} &&
        UPSTREAM_BASE_FORMAT=$(curl --silent --fail ${UPSTREAM_URL}${UPSTREAM_BASE_VERSION}/format)
    } || {
        echo "Failed to get ClearLinux upstream latest version information!"
        exit 4
    }

    if [ -z ${MIX_LATEST_VERSION} ]; then
        echo "INFO: No latest Mix, building the first mix"
        MIX_VERSION=${MIX_VERSION:-$(( ${UPSTREAM_BASE_VERSION} * 1000 + ${MIX_INCREMENT}))}

        MIX_LATEST_VERSION=${MIX_VERSION}
        MIX_LATEST_FORMAT=0

        UPSTREAM_PREV_VERSION=${UPSTREAM_BASE_VERSION}
        UPSTREAM_PREV_FORMAT=${UPSTREAM_BASE_FORMAT}
    else
        echo "INFO: Latest mix is ${MIX_LATEST_VERSION}, building"

        { # Get Latest Mix version's format (we already have the version)
            MIX_LATEST_FORMAT=$(curl --silent --fail file://${STAGING_DIR}/update/${MIX_LATEST_VERSION}/format)
        } || { # Failed
            echo "Failed to get latest mix format!"
            exit 2
        }

        MIX_VERSION=${MIX_VERSION:-$(( ${UPSTREAM_BASE_VERSION} * 1000 + ${MIX_INCREMENT}))}

        UPSTREAM_PREV_VERSION=${MIX_LATEST_VERSION::-3}

        { # Get the Upstream version and format for the previous mix
            UPSTREAM_PREV_FORMAT=$(curl --silent --fail ${UPSTREAM_URL}${UPSTREAM_PREV_VERSION}/format)
        } || { # Failed
            echo "Failed to get Upstream previous ClearLinux version information!"
            exit 2
        }

        if [ ${VERBOSE} ]; then
            echo "Upstream previous ClearLinux Version: ${UPSTREAM_PREV_VERSION}:${UPSTREAM_PREV_FORMAT}"
        fi

        if [ ${MIX_VERSION} -le ${MIX_LATEST_VERSION} ]; then
            echo "New Mix Version ${MIX_VERSION} is than or equal to Latest Mix Version ${MIX_LATEST_VERSION}!"
            echo "Abort..."
            exit 0
        fi
    fi

    if [ ${VERBOSE} ]; then
        echo "Mix version to create: ${MIX_VERSION}"
        echo "Mix Latest Version: ${MIX_LATEST_VERSION}:${MIX_LATEST_FORMAT}"
        echo "Upstream Version as Base for new Mix: ${UPSTREAM_BASE_VERSION}:${UPSTREAM_BASE_FORMAT}"
    fi
}

download_bundles() {
    echo ""
    echo "Downloading Bundles ..."

    if [ -z ${MIX_DIR} ]; then
        MIX_DIR="mix-bundles"
    fi

    if [ -d ${MIX_DIR} ]; then
        # Rename any existing MIX directory
        /usr/bin/mv ${MIX_DIR} ${MIX_DIR}.$(date +%Y%m%d.%H%M%S)
    fi

    # Clone the Mix Bundles repo
    /usr/bin/git clone --quiet ${MIX_BUNDLES_URL} ${MIX_DIR}

    # Check the Bundle definitions for this base version of ClearLinux
    sudo -E mixer init-mix -config ${BUILDER_CONF} -clearver ${UPSTREAM_BASE_VERSION} -mixver ${MIX_VERSION}

    if [ -z ${INC_BUNDLES} ]; then
        # We want our mix always based on everything from ClearLinux
        sudo -E /usr/bin/cp -a clr-bundles/clr-bundles-${UPSTREAM_BASE_VERSION}/bundles/* ${MIX_DIR}/
    else
        # Only use the requested bundles
        # Need the eval to expand the variable and then have bash filename expansion work
        eval sudo -E /usr/bin/cp -a clr-bundles/clr-bundles-${UPSTREAM_BASE_VERSION}/bundles/{${INC_BUNDLES}} ${MIX_DIR}/
    fi

    sudo -E /usr/bin/rm -rf clr-bundles
    # Ensure our custom bundles replace any upstream files
    pushd ${MIX_DIR} > /dev/null
    /usr/bin/git reset --quiet --hard HEAD
    # Change back to previous working directory
    popd > /dev/null
}

download_mix_rpms() {
    if [ -z ${RPM_DIR} ]; then
        RPM_DIR="rpms"
    fi

    echo ""

    # Create and change to RPM target directory
    /usr/bin/mkdir -p ${RPM_DIR}
    pushd ${RPM_DIR} > /dev/null

    koji_cmd list-tagged --latest --quiet ${KOJI_RPM_TAG}
    if [ -z "${KOJI_CMD_RESULTS}" ]; then
        echo "Failed to get Mix packages!"
        exit 2
    fi

    download_rpms=$(echo "${KOJI_CMD_RESULTS}" | awk '{print $1}')

    for rpm in ${download_rpms}; do
        if [ ${VERBOSE} ]; then
            echo "Downloading RPMs for $rpm ..."
        fi

        koji_cmd download-build --quiet ${rpm} --topurl ${KOJI_TOPURL}
    done

    # Change back to previous working directory
    popd > /dev/null
}

generate_mix() {
    # Can we override the format in the build file?

    download_bundles
    download_mix_rpms # Pull down the RPMs from Downstream Koji

    # Create the local repo directory
    LOCAL_REPO=$(grep '^REPODIR' ${BUILDER_CONF} | awk -F= '{print $NF}')
    # Expand the environment variables
    LOCAL_REPO=$(echo $(eval echo ${LOCAL_REPO}))
    /usr/bin/mkdir -p ${LOCAL_REPO}

    echo ""
    echo "Adding RPMs ..."
    sudo -E mixer add-rpms -config ${BUILDER_CONF}

    echo ""
    echo "Creating chroots ..."
    sudo -E mixer build-chroots -config ${BUILDER_CONF}

    echo ""
    echo "Building update ..."
    sudo -E mixer build-update -config ${BUILDER_CONF}

    if [ ${MIX_LATEST_VERSION} -lt ${MIX_VERSION} ]; then
        echo ""
        echo "Generating upgrade packs ..."
        sudo -E mixer-pack-maker.sh --to ${MIX_VERSION} --from ${MIX_LATEST_VERSION} -S ${BUILD_DIR}/update
    fi

    echo -n ${MIX_VERSION} | sudo -E tee update/latest > /dev/null
}

main() {
    test_dir ${BUILD_DIR}
    pushd ${BUILD_DIR} > /dev/null

    # TODO: Remove if https://github.com/clearlinux/mixer-tools/pull/29
    # and https://github.com/clearlinux/bundle-chroot-builder/pull/12 are
    # merged, or remove the TODO if they are not.

    # Apply the BUILD_DIR path into the configuration file.
    sed "s#\${BUILD_DIR}#${BUILD_DIR}#" ${SCRIPT_DIR}/builder.conf.in > ${BUILD_DIR}/builder.conf

    get_latest_versions
    generate_mix

    popd > /dev/null
}

main
