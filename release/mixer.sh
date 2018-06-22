#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# CLR_BUNDLES: Subset of bundles to be used from upstream (instead of all)
# DS_BUNDLES:  Subset of bundles to be used from downstream (instead of all)
# MIN_VERSION: If this build should be a min version

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

fetch_bundles() {
    log_line "Fetching downstream bundles:"
    rm -rf ./local-bundles
    git clone --quiet ${BUNDLES_REPO} local-bundles
    log_line "OK!" 1
}

fetch_koji_rpms() {
    local result

    log_line "Fetching Package List:"
    if result=$(koji_cmd list-tagged --latest --quiet ${KOJI_TAG}); then
        awk '{print $1}' <<< ${result} > ${WORK_DIR}/${PKG_LIST_FILE}
    else
        log_line "No custom content was found." 1
        return 1
    fi
    log_line "OK!" 1

    section "Downloading RPMs"
    rm -rf local-rpms
    rm -rf local-yum

    mkdir -p local-yum
    mkdir -p local-rpms

    pushd local-rpms > /dev/null
    for rpm in $(cat ${WORK_DIR}/${PKG_LIST_FILE}); do
        log_line "${rpm}:"
        koji_cmd download-build -a x86_64 --quiet ${rpm}
        log_line "OK!" 1
    done
    popd > /dev/null
}

build_bundles() {
    section "Bundles"
    log_line "Updating Bundles List:"
    # Clean bundles file, otherwise mixer will use the outdated list
    # and cause an error if bundles happen to be deleted
    rm -f ./mixbundles

    log_line
    # Add the upstream Bundle definitions for this base version of ClearLinux
    mixer bundle add ${CLR_BUNDLES:-"--all-upstream"}

    # Add the downstream Bundle definitions
    mixer bundle add ${DS_BUNDLES:-"--all-local"}
    log_line

    log_line "Building Bundles:"
    log_line
    sudo -E mixer --native build bundles
    log_line
}

build_update() {
    local mix_ver="$1"

    section "'Update' Content"
    if ${MIN_VERSION:-false}; then
        sudo -E mixer --native build update --min-version=${mix_ver}
    else
        sudo -E mixer --native build update
    fi
}

build_deltas() {
    local mix_ver="$1"

    section "Deltas"
    if [[ -n "${DS_LATEST}" ]]; then
        sudo -E mixer --native build delta-packs --from ${DS_LATEST} --to ${mix_ver}
    else
        log "Skipping Delta Packs creation" "No previous version was found."
    fi
}

generate_mix() {
    if (( $# != 3 && $# != 5 )); then
        error "'generate_mix' requires either 3 or 5 arguments!"
        return 1
    fi

    local clear_ver="$1"
    local mix_ver="$2"
    local mix_format="$3"

    # Set the Mix Format
    sed -i -E -e "s/(FORMAT = )(.*)/\1\"${mix_format}\"/" mixer.state

    # Set Upstream and Mix versions
    mixer versions update --clear-version ${clear_ver} --mix-version ${mix_ver}

    build_bundles

    if (( $# == 5 )); then
        # This is a ghost mix!
        local fake_ver="$4"
        local fake_format="$5"

        # Fake version and format
        echo -n ${fake_ver} | sudo -E \
            tee "$BUILD_DIR/update/image/${mix_ver}/full/usr/share/clear/version" > /dev/null
        echo -n ${fake_format} | sudo -E \
            tee "$BUILD_DIR/update/image/${mix_ver}/full/usr/share/defaults/swupd/format" > /dev/null
    fi

    build_update ${mix_ver}

    build_deltas ${mix_ver}

    if (( $# != 5 )); then
        echo -n ${mix_ver} | sudo -E tee update/latest > /dev/null
    fi
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

section "Bootstrapping Mix Workspace"
mixer init --local-rpms
mixer config set Swupd.CONTENTURL "${DSTREAM_DL_URL}/update"
mixer config set Swupd.VERSIONURL "${DSTREAM_DL_URL}/update"

log_line "Looking for previous releases:"
if [[ -z ${DS_LATEST} ]]; then
    log_line "None found. This will be the first Mix!" 1
    DS_UP_FORMAT=${CLR_FORMAT}
    DS_UP_VERSION=${CLR_LATEST}
fi

section "Preparing Downstream Content"
fetch_bundles # Download the Downstream Bundles Repository
fetch_koji_rpms && mixer add-rpms || true

section "Building"
format_bumps=$(( ${CLR_FORMAT} - ${DS_UP_FORMAT} ))
(( ${format_bumps} )) && info "Format Bumps will be needed"

for (( bump=0 ; bump < ${format_bumps} ; bump++ )); do
    stage "Format Bump: $(( ${bump}++ )) of ${format_bumps}"

    ds_format=$(( ${DS_FORMAT} + ${bump} ))
    ds_format_next=$(( ${ds_format}++ ))
    log "Downstream Format" "From: ${ds_format} To: ${ds_format_next}"

    up_format=$(( ${DS_UP_FORMAT} + ${bump} ))
    up_format_next=$(( ${up_format}++ ))
    log "Upstream Format" "From: ${up_format} To: ${up_format_next}"

    # Get the First version for Upstream Next Format
    up_version_next=$(curl ${CLR_PUBLIC_DL_URL}/update/version/format${up_format_next}/first) || true
    if [[ -z ${up_version_next} ]]; then
        error "Failed to get First version for Upstream Format: ${up_format_next}!"
        exit 2
    fi
    ds_version_next=$(( ${up_version_next} * 1000 + ${MIX_INCREMENT} * 2 )) # Calculate the matching Downstream version

    # Get the Latest version for Upstream "current" Format
    up_version=$(curl ${CLR_PUBLIC_DL_URL}/update/version/format${up_format}/latest) || true
    if [[ -z ${up_version} ]]; then
        error "Failed to get Latest version for Upstream Format: ${up_format}."
        exit 2
    fi
    ds_version=$(( ${up_version} * 1000 + ${MIX_INCREMENT} )) # Calculate the matching Downstream version

    # ===========
    # Ghost Mix
    # ===========
    log "Ghost Mix:" "${ds_version} (${ds_format}) based on: ${up_version} (${up_format})"
    MIN_VERSION=true LOG_INDENT=1 generate_mix "${up_version}" "${ds_version}" "${ds_format}" "${ds_version_next}" "${ds_format_next}"

    # ===========
    # Regular Mix
    # ===========
    log "Regular Mix:" "${ds_version_next} (${ds_format_next}) based on: ${up_version_next} (${up_format_next})"
    MIN_VERSION=true LOG_INDENT=1 generate_mix "${up_version_next}" "${ds_version_next}" "${ds_format_next}"
done

if [[ -n "${ds_format_next}" ]]; then
    DS_FORMAT=${ds_format_next}
    var_save DS_FORMAT
fi

# Check if a final mix is required
if [[ -z "${ds_version_next}" || "${MIX_VERSION}" -gt "${ds_version_next}" ]]; then
    LOG_INDENT=1 generate_mix "${CLR_LATEST}" "${MIX_VERSION}" "${DS_FORMAT}"
else
    MIX_VERSION=${ds_version_next}
    MIX_UP_VERSION=${MIX_VERSION: : -3}
    MIX_DOWN_VERSION=${MIX_VERSION: -3}

    var_save MIX_VERSION
    var_save MIX_UP_VERSION
    var_save MIX_DOWN_VERSION
fi

popd > /dev/null
