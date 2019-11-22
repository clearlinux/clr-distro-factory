#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# CLR_BUNDLES: Subset of bundles to be used from upstream (instead of all)
# DS_BUNDLES:  Subset of bundles to be used from downstream (instead of all)
# IS_UPSTREAM: If this update stream is either an upstream or a downstream
# MIN_VERSION: If this build should be a min version

# shellcheck source=common.sh
# shellcheck disable=SC2013

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"

. ./config/config.sh

var_load_all

IS_UPSTREAM=${IS_UPSTREAM:-false}
NUM_DELTA_BUILDS=${NUM_DELTA_BUILDS:-10}
MIXER_OPTS=${MIXER_OPTS:-"--native"}

mixer_cmd() {
    # shellcheck disable=SC2086
    mixer ${MIXER_OPTS} "${@}"
}

sudo_mixer_cmd() {
    # shellcheck disable=SC2086
    sudo -E mixer ${MIXER_OPTS} "${@}"
}

fetch_bundles() {
    log_line "Fetching bundles:"
    local bundles_dir="${WORK_DIR}/bundles"
    git clone --quiet "${BUNDLES_REPO}" "${bundles_dir}"
    rm -rf ./local-bundles
    mv "${bundles_dir}/${BUNDLES_REPO_SRC_DIR}" ./local-bundles
    log_line "OK!" 1
}

build_bundles() {
    section "Bundles"
    log_line "Updating Bundles List:"
    # Clean bundles file, otherwise mixer will use the outdated list
    # and cause an error if bundles happen to be deleted
    rm -f ./mixbundles

    log_line
    if ! "${IS_UPSTREAM}"; then
        # Add the upstream Bundle definitions for this base version of ClearLinux
        # shellcheck disable=SC2086
        mixer_cmd bundle add ${CLR_BUNDLES:-"--all-upstream"}
    fi

    # Add the downstream Bundle definitions
    # shellcheck disable=SC2086
    mixer_cmd bundle add ${DS_BUNDLES:-"--all-local"}
    log_line

    log_line "Building Bundles:"
    log_line
    sudo_mixer_cmd build bundles
    log_line
}

build_update() {
    local mix_ver="$1"

    section "Build 'Update' Content"
    if ${MIN_VERSION:-false}; then
        sudo_mixer_cmd build update --skip-format-check --min-version="${mix_ver}"
    else
        sudo_mixer_cmd build update --skip-format-check
    fi
}

build_deltas() {
    local mix_format="${1}"

    section "Deltas"

    local first_file="update/www/version/format${mix_format}/first"
    if [[ -s "${first_file}" ]]; then
        local first_version="$(< "${first_file}")"
        log "Building deltas from the first build ${first_version} in format ${mix_format}..."
        sudo_mixer_cmd build delta-packs --from "${first_version}"
        sudo_mixer_cmd build delta-manifests --from "${first_version}"
    else
        log "Skipping delta creation from the first build ${first_version} in format ${mix_format}" "'first' file not found for format ${mix_format}"
    fi

    if (( NUM_DELTA_BUILDS > 0 )); then
        log "Building deltas for the previous ${NUM_DELTA_BUILDS} builds..." 1
        sudo_mixer_cmd build delta-packs --previous-versions "${NUM_DELTA_BUILDS}"
        sudo_mixer_cmd build delta-manifests --previous-versions "${NUM_DELTA_BUILDS}"
    else
        log "Skipping delta creation for the previous ${NUM_DELTA_BUILDS} builds" "'NUM_DELTA_BUILDS' <= 0"
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
    mixer_cmd versions update --clear-version "${clear_ver}" --mix-version "${mix_ver}" --skip-format-check

    build_bundles

    # Remove bundles pending deletion
    section "Bundle Deletion"
    local bundle_folders
    if "${IS_UPSTREAM}"; then
        bundle_folders="local-bundles/"
    else
        bundle_folders="upstream-bundles/ local-bundles/"
    fi
    # shellcheck disable=SC2086
    for i in $(grep -lir "\\[STATUS\\]: Pending-Delete" ${bundle_folders}); do
        b=$(basename "$i")
        log "Deleting" "${b}"
        sudo -E rm -f "update/image/${mix_ver}/${b}-info"
        sudo -E mkdir -p "update/image/${mix_ver}/${b}"
    done # TODO

    # Fake version and format
    sudo -E sed -i -E -e "s/(VERSION_ID=)(.*)/\\1\"${mix_ver_next}\"/" \
        "${MIXER_DIR}/update/image/${mix_ver}/full/usr/lib/os-release"
    echo -n "${mix_ver_next}" | sudo -E \
        tee "${MIXER_DIR}/update/image/${mix_ver}/full/usr/share/clear/version" > /dev/null
    echo -n "${mix_format_next}" | sudo -E \
        tee "${MIXER_DIR}/update/image/${mix_ver}/full/usr/share/defaults/swupd/format" > /dev/null

    build_update "${mix_ver}"

    build_deltas "${mix_format}"

    # Bumped Build (+20)
    # Set the Mix Format
    section "Building +20"
    sed -i -E -e "s/(FORMAT = )(.*)/\\1\"${mix_format_next}\"/" mixer.state

    # Set Upstream and Mix versions
    mixer_cmd versions update --clear-version "${clear_ver_next}" --mix-version "${mix_ver_next}" --offline --skip-format-check

    # Remove bundles pending deletion again
    section "Bundle Deletion"
    for i in $(grep -lir "\\[STATUS\\]: Pending-Delete" upstream-bundles/ local-bundles/); do
        b=$(basename "$i")
        log "Deleting" "${b}"
        mixer_cmd bundle remove "${b}"
        sudo -E sed -i -E -e "/\\[${b}\\]/d;/group=${b}/d" "${MIXER_DIR}/update/groups.ini"
    done #TODO: Maybe also delete from bundles repository?

    # "build bundles"
    section "Fake Build Bundles"
    sudo -E cp -al "${MIXER_DIR}/update/image/${mix_ver}" "${MIXER_DIR}/update/image/${mix_ver_next}"

    MIN_VERSION=true build_update "${mix_ver_next}"

    echo -n "${mix_ver_next}" | sudo -E tee update/latest > /dev/null
    echo -n "${mix_ver_next}" | sudo -E tee "update/www/version/format${mix_format_next}/first" > /dev/null
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
    mixer_cmd versions update --clear-version "${clear_ver}" --mix-version "${mix_ver}" --skip-format-check

    build_bundles

    build_update "${mix_ver}"

    build_deltas "${mix_format}"

    echo -n "${mix_ver}" | sudo -E tee update/latest > /dev/null
}

# ==============================================================================
# MAIN
# ==============================================================================
stage Mixer
pushd "${MIXER_DIR}" > /dev/null

section "Bootstrapping Mix Workspace"
mixer_cmd init --upstream-url "${CLR_PUBLIC_DL_URL}" --upstream-version "${CLR_LATEST}"
mixer_cmd config set Swupd.CONTENTURL "${DISTRO_URL}/update"
mixer_cmd config set Swupd.VERSIONURL "${DISTRO_URL}/update"

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
if [[ -z "${BUNDLES_REPO}" ]]; then
    info "Custom bundles not found" "'BUNDLES_REPO' is empty"
else
    fetch_bundles # Download the Downstream Bundles Repository
fi

log_line "Checking Downstream Repo:"
if [[ -n "$(ls -A "${PKGS_DIR}")" ]];then
    mixer_cmd config set Mixer.LOCAL_RPM_DIR "${REPO_DIR}/x86_64/os/Packages"
    mixer_cmd add-rpms > /dev/null
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
