#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# CLR_BUNDLES: Subset of bundles to be used from upstream (instead of all)
# DS_BUNDLES:  Subset of bundles to be used from downstream (instead of all)
# MIN_VERSION: If this build should be a min version

# shellcheck source=globals.sh
# shellcheck source=common.sh
# shellcheck disable=SC2013

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../globals.sh"
. "${SCRIPT_DIR}/../common.sh"

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
    git clone --quiet "${BUNDLES_REPO}" local-bundles
    log_line "OK!" 1
}

build_bundles() {
    section "Bundles"
    log_line "Updating Bundles List:"
    # Clean bundles file, otherwise mixer will use the outdated list
    # and cause an error if bundles happen to be deleted
    rm -f ./mixbundles

    log_line
    # Add the upstream Bundle definitions for this base version of ClearLinux
    # shellcheck disable=SC2086
    mixer bundle add ${CLR_BUNDLES:-"--all-upstream"}

    # Add the downstream Bundle definitions
    # shellcheck disable=SC2086
    mixer bundle add ${DS_BUNDLES:-"--all-local"}
    log_line

    log_line "Building Bundles:"
    log_line
    sudo -E mixer --native build bundles
    log_line
}

build_update() {
    local mix_ver="$1"

    section "Build 'Update' Content"
    if ${MIN_VERSION:-false}; then
        sudo -E mixer --native build update --min-version="${mix_ver}"
    else
        sudo -E mixer --native build update
    fi
}

build_deltas() {
    local mix_ver="$1"

    section "Deltas"
    if [[ -n "${DS_LATEST}" ]]; then
        sudo -E mixer --native build delta-packs --from "${DS_LATEST}" --to "${mix_ver}"
    else
        log "Skipping Delta Packs creation" "No previous version was found."
    fi
}

generate_bump() {
    if (($# != 6 )); then
        error "'generate_format_bump' requires 6 arguments!"
        return 1
    fi

    local clear_ver="$1"
    local mix_ver="$2"
    local mix_format="$3"
    local clear_ver_next="$4"
    local mix_ver_next="$5"
    local mix_format_next="$6"

    # Ghost Build (+10)
    # Set the Mix Format
    section "Building +10"
    sed -i -E -e "s/(FORMAT = )(.*)/\\1\"${mix_format}\"/" mixer.state

    # Set Upstream and Mix versions
    mixer versions update --clear-version "${clear_ver}" --mix-version "${mix_ver}"

    build_bundles

    # Delete deprecated bundles
    section "Bundle Deletion"
    for i in $(grep -lir "\\[STATUS\\]: Deprecated" upstream-bundles/ local-bundles/); do
        b=$(basename "$i")
        log "Deleting" "${b}"
        sudo -E rm -f "update/image/${mix_ver}/${b}-info"
        sudo -E mkdir -p "update/image/${mix_ver}/${b}"
    done # TODO

    # Fake version and format
    sudo -E sed -i -E -e "s/(VERSION_ID=)(.*)/\\1\"${mix_ver_next}\"/" \
        "${BUILD_DIR}/update/image/${mix_ver}/full/usr/lib/os-release"
    echo -n "${mix_ver_next}" | sudo -E \
        tee "${BUILD_DIR}/update/image/${mix_ver}/full/usr/share/clear/version" > /dev/null
    echo -n "${mix_format_next}" | sudo -E \
        tee "${BUILD_DIR}/update/image/${mix_ver}/full/usr/share/defaults/swupd/format" > /dev/null

    build_update "${mix_ver}"

    build_deltas "${mix_ver}"

    # Bumped Build (+20)
    # Set the Mix Format
    section "Building +20"
    sed -i -E -e "s/(FORMAT = )(.*)/\\1\"${mix_format_next}\"/" mixer.state

    # Set Upstream and Mix versions
    mixer versions update --clear-version "${clear_ver_next}" --mix-version "${mix_ver_next}" --offline

    # Delete deprecated bundles again
    section "Bundle Deletion"
    for i in $(grep -lir "\\[STATUS\\]: Deprecated" upstream-bundles/ local-bundles/); do
        b=$(basename "$i")
        log "Deleting" "${b}"
        mixer bundle remove "${b}"
        sudo -E sed -i -E -e "/\\[${b}\\]/d;/group=${b}/d" "${BUILD_DIR}/update/groups.ini"
    done #TODO: Maybe also delete from bundles repository?

    # "build bundles"
    section "Fake Build Bundles"
    sudo -E cp -al "${BUILD_DIR}/update/image/${mix_ver}" "${BUILD_DIR}/update/image/${mix_ver_next}"

    MIN_VERSION=true build_update "${mix_ver_next}"

    echo -n "${mix_ver_next}" | sudo -E tee update/latest > /dev/null
}

generate_mix() {
    if (( $# != 3 )); then
        error "'generate_mix' (regular build) requires 3 arguments!"
        return 1
    fi

    local clear_ver="$1"
    local mix_ver="$2"
    local mix_format="$3"

    # Set the Mix Format
    sed -i -E -e "s/(FORMAT = )(.*)/\\1\"${mix_format}\"/" mixer.state

    # Set Upstream and Mix versions
    mixer versions update --clear-version "${clear_ver}" --mix-version "${mix_ver}"

    build_bundles

    build_update "${mix_ver}"

    build_deltas "${mix_ver}"

    echo -n "${mix_ver}" | sudo -E tee update/latest > /dev/null
}

# ==============================================================================
# MAIN
# ==============================================================================
stage Mixer
pushd "${BUILD_DIR}" > /dev/null

section "Bootstrapping Mix Workspace"
mixer init --upstream-url "${CLR_PUBLIC_DL_URL}" --upstream-version "${CLR_LATEST}"
mixer config set Swupd.CONTENTURL "${DSTREAM_DL_URL}/update"
mixer config set Swupd.VERSIONURL "${DSTREAM_DL_URL}/update"

log_line "Looking for previous releases:"
if [[ -z ${DS_LATEST} ]]; then
    log_line "None found. This will be the first Mix!" 1
    DS_UP_FORMAT=${CLR_FORMAT}
    # shellcheck disable=SC2034
    DS_UP_VERSION=${CLR_LATEST}

    var_save DS_UP_FORMAT
    var_save DS_UP_VERSION
fi

MCA_VERSIONS="${DS_LATEST}"

section "Preparing Downstream Content"
fetch_bundles # Download the Downstream Bundles Repository

log_line "Checking Downstream Repo:"
if [[ -n "$(ls -A "${PKGS_DIR}")" ]];then
    mixer repo set-url content "file://${REPO_DIR}/x86_64/os" > /dev/null
    log_line "Content found. Adding it to the mix!" 1
else
    log_line "Content not found. Skipping it." 1
fi

section "Building"
format_bumps=$(( CLR_FORMAT - DS_UP_FORMAT ))
(( format_bumps )) && info "Format Bumps will be needed"
#TODO: Check for required mixer version for the bump here

for (( bump=0 ; bump < format_bumps ; bump++ )); do
    section "Format Bump: $(( bump + 1 )) of ${format_bumps}"

    ds_fmt=$(( DS_FORMAT + bump ))
    ds_fmt_next=$(( ds_fmt + 1 ))
    log "Downstream Format" "From: ${ds_fmt} To: ${ds_fmt_next}"

    up_fmt=$(( DS_UP_FORMAT + bump ))
    up_fmt_next=$(( up_fmt + 1 ))
    log "Upstream Format" "From: ${up_fmt} To: ${up_fmt_next}"

    # Get the First version for Upstream Next Format
    up_ver_next=$(curl "${CLR_PUBLIC_DL_URL}/update/version/format${up_fmt_next}/first") || true
    if [[ -z ${up_ver_next} ]]; then
        error "Failed to get First version for Upstream Format: ${up_fmt_next}!"
        exit 2
    fi
    # Calculate the matching Downstream version
    ds_ver_next=$(( up_ver_next * 1000 + MIX_INCREMENT * 2 ))

    # Get the Latest version for Upstream "current" Format
    up_ver=$(curl "${CLR_PUBLIC_DL_URL}/update/version/format${up_fmt}/latest") || true
    if [[ -z ${up_ver} ]]; then
        error "Failed to get Latest version for Upstream Format: ${up_fmt}."
        exit 2
    fi
    # Calculate the matching Downstream version
    ds_ver=$(( up_ver * 1000 + MIX_INCREMENT ))

    log "+10 Mix:" "${ds_ver} (${ds_fmt}) based on: ${up_ver} (${up_fmt})"
    log "+20 Mix:" "${ds_ver_next} (${ds_fmt_next}) based on: ${up_ver_next} (${up_fmt_next})"
    generate_bump "${up_ver}" "${ds_ver}" "${ds_fmt}" "${up_ver_next}" "${ds_ver_next}" "${ds_fmt_next}"

    MCA_VERSIONS+=" ${ds_ver} ${ds_ver_next}"
done

if [[ -n "${ds_fmt_next}" ]]; then
    DS_FORMAT=${ds_fmt_next}
    var_save DS_FORMAT
fi

if [[ -z "${ds_ver_next}" || "${MIX_VERSION}" -gt "${ds_ver_next}" ]]; then
    log_line
    log "Regular Mix:" "${MIX_VERSION} (${DS_FORMAT}) based on: ${CLR_LATEST} (${CLR_FORMAT})"
    generate_mix "${CLR_LATEST}" "${MIX_VERSION}" "${DS_FORMAT}"

    MCA_VERSIONS+=" ${MIX_VERSION}"
else
    MIX_VERSION=${ds_ver_next}
    # shellcheck disable=SC2034
    MIX_UP_VERSION=${MIX_VERSION: : -3}
    # shellcheck disable=SC2034
    MIX_DOWN_VERSION=${MIX_VERSION: -3}

    var_save MIX_VERSION
    var_save MIX_UP_VERSION
    var_save MIX_DOWN_VERSION
fi

var_save MCA_VERSIONS

popd > /dev/null
