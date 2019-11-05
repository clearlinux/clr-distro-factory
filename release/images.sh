#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# IMG_SIGN_CMD: (Optional) Custom command to be used for signing image checksum files.
# IMG_SIGN_KEY: (Optional) Private key to be used for signing image checksum files with 'openssl'.

# shellcheck source=common.sh

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"
. "${SCRIPT_DIR}/../config/config.sh"

var_load MIX_VERSION
var_load DS_FORMAT

IMGS_DIR="${WORK_DIR}/release/images"
LOG_DIR="${WORK_DIR}/logs"
PROCS_PER_IMG=8
TEMPLATES_PATH=${TEMPLATES_PATH:-"${PWD}/config/images"}

checksum_and_sign() {
    # ${1} - Where to output the list of files, checksum & signed files -> release dir
    # ${2} - File path to image file
    declare -n _output=${1}
    local file_list=$2

    for file in ${file_list}; do
        local chksum_file="${file}-${CHKSUM_FILE_SUFFIX}"

        sha512sum "${file}" > "${chksum_file}"

        if [[ -n "${IMG_SIGN_CMD}" ]]; then
            log "Signing (custom)" "${chksum_file}"
            "${IMG_SIGN_CMD}" "${chksum_file}" "${chksum_file}.sig"
        elif [[ -s "${IMG_SIGN_KEY}" ]]; then
            log "Signing (openssl)" "${chksum_file}"
            openssl dgst -sha1 -sign "${IMG_SIGN_KEY}" -out "${chksum_file}.sig" "${chksum_file}"
        else
            warn "Skipping signing" "Neither custom signing command nor a signing key provided."
        fi
        _output+="${file} ${chksum_file} ${chksum_file}.sig " # space is not a mistake
    done
}

finalize_image() {
    # ${1} - Where to output the list of finalized images -> release dir
    # ${2} - File path to image file
    declare -n _output=${1}
    local file_list=("${2}")
    local name="$(basename "${file_list[0]}")"
    local finalize_script="$(find "${TEMPLATES_PATH}" -name "${name%.*}-finalize.*" -print -quit)"

    if [[ -z "${name}" ]]; then
        error "Image finalization failed. Invalid input" "${2}"
        return 1
    fi

    for image_file in "${file_list[@]}"; do
        if [[ -s "${finalize_script}" ]]; then
            if ! image_file=$("${finalize_script}" "${image_file}"); then
                warn "${name}" "Image finalization failed"
                return 1
            fi
        fi

        local final_path="$(dirname "${image_file}")/${DISTRO_NAME}-${MIX_VERSION}-$(basename "${image_file}")"
        mv "${image_file}" "${final_path}"

        _output+="${final_path} " # Space is not a mistake
    done
}

create_image() {
    # ${1} - Where to output the list of created images
    # ${2} - File path to image template file
    declare -n _output=${1}
    local image=${2}
    local name=$(basename "${image%.yaml}")
    local log_file="${LOG_DIR}/clr-installer-${name}.log"

    if [[ -z "${image}" || -z "${name}" ]]; then
        error "Image creation failed. Invalid input" "${2}"
        return 1
    fi

    pushd "${WORK_DIR}" > /dev/null

    sudo -E clr-installer --config "${image}" --log-level=4 \
        --swupd-format "${DS_FORMAT}" --swupd-clean \
        --swupd-cert "${MIXER_DIR}/Swupd_Root.pem" \
        --swupd-contenturl "file://${MIXER_DIR}/update/www" \
        --swupd-versionurl "file://${MIXER_DIR}/update/www" \
        --log-file "${log_file}" &> /dev/null
    # cmd is way too large to embed on a 'if' statement
    # shellcheck disable=2181
    if (( $? )); then
        log "Image '${name}'" "Failed. See log below:"
        echo
        cat "${log_file}"
        echo
        return 1
    fi

    popd > /dev/null
    _output=$(ls "${WORK_DIR}/${name}".*)
    log "Image '${name}'" "OK!"
}

parallel_fn() {
    # Intended to be used only by GNU Parallel
    . "${SCRIPT_DIR}/../globals.sh"
    . "${SCRIPT_DIR}/../common.sh"
    . "${SCRIPT_DIR}/../config/config.sh"

    local image_files
    local finalized_files
    local final_files

    create_image "image_files" "$@"
    finalize_image "finalized_files" "${image_files}"
    if checksum_and_sign "final_files" "${finalized_files}"; then
        warn "$(basename "${image_files%.*}")" "Image signing failed"
        return 1
    fi
    mv "${final_files}" "${IMGS_DIR}"
}

# ==============================================================================
# MAIN
# ==============================================================================
stage "Image Generation"

# shellcheck disable=2086
image_list=$(ls ${TEMPLATES_PATH}/*.yaml 2>/dev/null || true)

if [[ -z "${image_list}" ]]; then
    warn "Skipping stage."
    warn "No image definition files found in" "${TEMPLATES_PATH}"
    exit 0
fi

mkdir -p "${LOG_DIR}"

export IMGS_DIR
export LOG_DIR
export MIX_VERSION
export DS_FORMAT
export SCRIPT_DIR
export TEMPLATES_PATH
export -f create_image
export -f finalize_image
export -f checksum_and_sign
export -f parallel_fn
procs=$(nproc --all)
max_jobs=$(( ${procs:=0} > PROCS_PER_IMG ? procs / PROCS_PER_IMG : 1 ))
parallel -j ${max_jobs} parallel_fn <<< "${image_list}"
