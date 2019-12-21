#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# CLR_BUNDLES:     Subset of bundles to be used from upstream (instead of all)
# DISTRO_BUNDLES:  Subset of bundles to be used from local (instead of all)

# shellcheck source=common.sh
# shellcheck disable=SC2013

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"

. ./config/config.sh

var_load_all

if ! "${IS_DOWNSTREAM}" && [[ ${MIXER_OPTS} != *"--offline"* ]]; then
    log "'IS_DOWNSTREAM' flag is not set" "Setting '--offline' flag to mixer"
    MIXER_OPTS="${MIXER_OPTS} --offline"
fi

build_bundles() {
    section "Bundles"
    log_line "Updating Bundles List:"
    # Clean bundles file, otherwise mixer will use the outdated list
    # and cause an error if bundles happen to be deleted
    rm -f ./mixbundles

    log_line
    if "${IS_DOWNSTREAM}"; then
        # Add the upstream Bundle definitions for this base version of ClearLinux
        # shellcheck disable=SC2086
        mixer_cmd bundle add ${CLR_BUNDLES:-"--all-upstream"}
    fi

    # Add the local Bundle definitions
    # shellcheck disable=SC2086
    mixer_cmd bundle add ${DISTRO_BUNDLES:-"--all-local"}
    log_line

    log_line "Building Bundles:"
    log_line
    local mixer_opts_bundles=""
    if function_exists sign_update; then
        mixer_opts_bundles+=" --no-signing"
    fi

    # shellcheck disable=SC2086
    sudo_mixer_cmd build bundles ${mixer_opts_bundles}
    log_line
}

build_update() {
    local mix_ver="$1"

    section "Build 'Update' Content"

    local mixer_opts_update="--skip-format-check"
    if "${MIN_VERSION}"; then
        mixer_opts_update+=" --min-version=${mix_ver}"
    fi
    if function_exists sign_update; then
        mixer_opts_update+=" --no-signing"
    fi

    # shellcheck disable=SC2086
    sudo_mixer_cmd build update ${mixer_opts_update}

    if function_exists sign_update; then
        pushd "update/www/${mix_ver}" > /dev/null
        log "Signing update (custom)" "${PWD}/Manifest.MoM"
        sign_update Manifest.MoM Manifest.MoM.sig
        sudo rm -f Manifest.MoM.tar
        sudo tar -cJf Manifest.MoM.tar Manifest.MoM Manifest.MoM.sig
        popd > /dev/null
    fi
}

build_deltas() {
    local mix_format="${1}"

    section "Deltas"

    local first_file="update/www/version/format${mix_format}/first"
    if [[ -s "${first_file}" ]]; then
        local first_version="$(< "${first_file}")"
        log "Building deltas from the first build ${first_version} in format ${mix_format}..."
        if ! sudo_mixer_cmd build delta-packs --from "${first_version}"; then
            warn "First file found. But delta-packs failed to be created."
        fi
        if ! sudo_mixer_cmd build delta-manifests --from "${first_version}"; then
            warn "First file found. But delta-manifest failed to be created."
        fi
    else
        log "Skipping delta creation from the first build ${first_version} in format ${mix_format}" "'first' file not found for format ${mix_format}"
    fi

    if (( NUM_DELTA_BUILDS > 0 )); then
        log "Building deltas for the previous ${NUM_DELTA_BUILDS} builds..."
        if ! sudo_mixer_cmd build delta-packs --previous-versions "${NUM_DELTA_BUILDS}"; then
            warn "Previous builds found. But delta-packs failed to be created."
        fi
        if ! sudo_mixer_cmd build delta-manifests --previous-versions "${NUM_DELTA_BUILDS}"; then
            warn "Previous builds found. But delta-manifests failed to be created."
        fi
    else
        log "Skipping delta creation for the previous ${NUM_DELTA_BUILDS} builds" "'NUM_DELTA_BUILDS' <= 0"
    fi
}

generate_bump() {
    if (( $# < 4 )); then
        error "'generate_format_bump' requires at least 4 arguments!"
        return 1
    fi

    local mix_ver="$1"
    local mix_format="$2"
    local mix_ver_next="$3"
    local mix_format_next="$4"
    local clear_ver="$5"
    local clear_ver_next="$6"

    # Ghost Build (+10)
    # Set the Mix Format
    section "Building +10"
    sed -i -E -e "s/(FORMAT = )(.*)/\\1\"${mix_format}\"/" mixer.state

    # Set Upstream and Mix versions
    local mixer_opts="--skip-format-check --mix-version ${mix_ver}"
    if "${IS_DOWNSTREAM}"; then
        mixer_opts+=" --clear-version ${clear_ver}"
    fi

    # shellcheck disable=SC2086
    mixer_cmd versions update ${mixer_opts}

    build_bundles

    # Remove bundles pending deletion
    section "Bundle Deletion"
    local bundle_folders
    if "${IS_DOWNSTREAM}"; then
        bundle_folders="upstream-bundles/ local-bundles/"
    else
        bundle_folders="local-bundles/"
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
    mixer_opts="--offline --skip-format-check --mix-version ${mix_ver_next}"
    if "${IS_DOWNSTREAM}"; then
        mixer_opts+=" --clear-version ${clear_ver_next}"
    fi

    # shellcheck disable=SC2086
    mixer_cmd versions update ${mixer_opts}

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
    if (( $# < 2 )); then
        error "'generate_mix' (regular build) requires at least 2 arguments!"
        return 1
    fi

    local mix_ver="$1"
    local mix_format="$2"
    local clear_ver="$3"

    # Set the Mix Format
    sed -i -E -e "s/(FORMAT = )(.*)/\\1\"${mix_format}\"/" mixer.state

    # Set Upstream and Mix versions
    local mixer_opts="--skip-format-check --mix-version ${mix_ver}"
    if "${IS_DOWNSTREAM}"; then
        mixer_opts+=" --clear-version ${clear_ver}"
    fi

    # shellcheck disable=SC2086
    mixer_cmd versions update ${mixer_opts}

    build_bundles

    build_update "${mix_ver}"

    build_deltas "${mix_format}"

    echo -n "${mix_ver}" | sudo -E tee update/latest > /dev/null
}

downstream_build() {
    format_bumps=$(( CLR_FORMAT - DISTRO_UP_FORMAT ))

    for (( bump=0 ; bump < format_bumps ; bump++ )); do
        section "Format Bump: $(( bump + 1 )) of ${format_bumps}"

        distro_fmt=$(( DISTRO_FORMAT + bump ))
        distro_fmt_next=$(( distro_fmt + 1 ))
        log "Distribution Format" "From: ${distro_fmt} To: ${distro_fmt_next}"

        up_fmt=$(( DISTRO_UP_FORMAT + bump ))
        up_fmt_next=$(( up_fmt + 1 ))
        log "Upstream Format" "From: ${up_fmt} To: ${up_fmt_next}"

        # Get the First version for Upstream Next Format
        up_ver_next=$(curl "${CLR_PUBLIC_DL_URL}/update/version/format${up_fmt_next}/first") || true
        if [[ -z ${up_ver_next} ]]; then
            error "Failed to get First version for Upstream Format: ${up_fmt_next}!"
            exit 2
        fi
        # Calculate the matching Distribution version
        distro_ver_next=$(( up_ver_next * 1000 + MIX_INCREMENT * 2 ))

        # Get the Latest version for Upstream "current" Format
        up_ver=$(curl "${CLR_PUBLIC_DL_URL}/update/version/format${up_fmt}/latest") || true
        if [[ -z ${up_ver} ]]; then
            error "Failed to get Latest version for Upstream Format: ${up_fmt}."
            exit 2
        fi
        # Calculate the matching Distribution version
        distro_ver=$(( up_ver * 1000 + MIX_INCREMENT ))

        log "+10 Mix:" "${distro_ver} (${distro_fmt}) based on: ${up_ver} (${up_fmt})"
        log "+20 Mix:" "${distro_ver_next} (${distro_fmt_next}) based on: ${up_ver_next} (${up_fmt_next})"
        generate_bump "${distro_ver}" "${distro_fmt}" "${distro_ver_next}" "${distro_fmt_next}" "${up_ver}" "${up_ver_next}"

        MCA_VERSIONS+=" ${distro_ver} ${distro_ver_next}"
    done

    if [[ -n "${distro_fmt_next}" ]]; then
        MIX_FORMAT=${distro_fmt_next}
        var_save MIX_FORMAT
    fi

    if [[ -z "${distro_ver_next}" || "${MIX_VERSION}" -gt "${distro_ver_next}" ]]; then
        # In this case, final MIX_VERSION estimate is correct and a final mix is needed
        log_line
        log "Regular Mix" "${MIX_VERSION} (${MIX_FORMAT}) based on: ${CLR_LATEST} (${CLR_FORMAT})"
        generate_mix "${MIX_VERSION}" "${MIX_FORMAT}" "${CLR_LATEST}"

        MCA_VERSIONS+=" ${MIX_VERSION}"
    else
        # If a format bump was performed and a catch-up mix was not needed,
        # then initial estimate needs to be fixed.
        MIX_VERSION=${distro_ver_next}
        # shellcheck disable=SC2034
        MIX_UP_VERSION=${MIX_VERSION: : -3}
        # shellcheck disable=SC2034
        MIX_DOWN_VERSION=${MIX_VERSION: -3}

        var_save MIX_VERSION
        var_save MIX_UP_VERSION
        var_save MIX_DOWN_VERSION
    fi
}

upstream_build() {
    if "${FORMAT_BUMP}"; then
        mix_10=$(( MIX_VERSION - MIX_INCREMENT ))
        log "+10 Mix:" "${mix_10} (${DISTRO_FORMAT})"
        log "+20 Mix:" "${MIX_VERSION} (${MIX_FORMAT})"
        generate_bump "${mix_10}" "${DISTRO_FORMAT}" "${MIX_VERSION}" "${MIX_FORMAT}"
        MCA_VERSIONS+=" ${mix_10} ${MIX_VERSION}"
    else
        log "Regular Mix" "${MIX_VERSION} (${MIX_FORMAT})"
        generate_mix "${MIX_VERSION}" "${MIX_FORMAT}"
        MCA_VERSIONS+=" ${MIX_VERSION}"
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================
stage Mixer
pushd "${MIXER_DIR}" > /dev/null

section "Bootstrapping Mix Workspace"
log_line "Looking for previous releases:"
if [[ -z "${DISTRO_LATEST}" ]]; then
    log_line "None found. This will be the first Mix!" 1

    log_line "Initializing Mixer Workspace"
    if "${IS_DOWNSTREAM}"; then
        mixer_cmd init --upstream-url "${CLR_PUBLIC_DL_URL}" --upstream-version "${CLR_LATEST}"
    else
        #note: --offline is already set
        mixer_cmd init --upstream-url "${DISTRO_URL}" --upstream-version "${MIX_VERSION}"
    fi
    log_line ""
else
    echo "${DISTRO_LATEST}" > mixversion
    sed -i -E -e "s/(PREVIOUS_MIX_VERSION = )(.*)/\\1\"${DISTRO_LATEST}\"/" mixer.state
fi

if ! "${IS_DOWNSTREAM}"; then
    log_line "Making sure 'clear' repo does not exists:"
    mixer_cmd repo remove "clear" || true
fi

mixer_cmd config set Swupd.CONTENTURL "${DISTRO_URL}/update"
mixer_cmd config set Swupd.VERSIONURL "${DISTRO_URL}/update"

MCA_VERSIONS="${DISTRO_LATEST}"

section "Preparing Mix Content"

log_line "Checking Local Bundles:"
rm -rf ./local-bundles
if [[ -d "${BUNDLES_DIR}/${BUNDLES_REPO_SRC_DIR}" ]] \
    && [[ -n "$(ls -A "${BUNDLES_DIR}/${BUNDLES_REPO_SRC_DIR}")" ]]; then
    log_line "Bundles found. Adding it to the mix!" 1
    cp -r "${BUNDLES_DIR}/${BUNDLES_REPO_SRC_DIR}" ./local-bundles
else
    mkdir ./local-bundles
    log_line "Bundles not found. Skipping it." 1
fi

log_line "Checking Local Packages Repo:"
if [[ -n "$(ls -A "${PKGS_DIR}")" ]];then
    log_line "Content found. Adding it to the mix!" 1
    mixer_cmd config set Mixer.LOCAL_RPM_DIR "${PKGS_DIR}"
    mixer_cmd add-rpms > /dev/null
else
    log_line "Content not found. Skipping it." 1
fi

section "Building"
if "${IS_DOWNSTREAM}"; then
    downstream_build
else
    upstream_build
fi

var_save MCA_VERSIONS
popd > /dev/null
