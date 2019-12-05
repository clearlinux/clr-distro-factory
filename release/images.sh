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

sign_checksum() {
    local chksum_file=$1

    if [[ -n "${IMG_SIGN_CMD}" ]]; then
        log "Signing (custom)" "${chksum_file}"
        "${IMG_SIGN_CMD}" "${chksum_file}" "${chksum_file}.sig"
    elif [[ -s "${IMG_SIGN_KEY}" ]]; then
        log "Signing (openssl)" "${chksum_file}"
        openssl dgst -sha1 -sign "${IMG_SIGN_KEY}" -out "${chksum_file}.sig" "${chksum_file}"
    else
        warn "Skipping signing" "Neither custom signing command nor a signing key provided."
    fi
}

create_image() {
    # ${1} - File path to image template file
    local image=${1}
    local name=$(basename "${image%.yaml}")
    local log_file="${LOG_DIR}/clr-installer-${name}.log"
    local final_file="${IMGS_DIR}/${DISTRO_NAME}-${MIX_VERSION}-${name}"

    if [[ -z "${image}" || -z "${name}" ]]; then
        error "Image creation failed. Invalid input" "${1}"
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

    if [[ -s "${name}.img" ]]; then
        xz -3 --stdout "${name}.img" > "${final_file}.img.xz"
        sudo rm "${name}.img"

        if [[ ! -s "${final_file}.img.xz" ]]; then
            log "Image '${name}'" "Failed to create compressed file."
            return 1
        fi
        sha512sum "${final_file}.img.xz" > "${final_file}.img.xz-${CHKSUM_FILE_SUFFIX}"
        sign_checksum "${final_file}.img.xz-${CHKSUM_FILE_SUFFIX}"
    fi

    if [[ -s "${name}.iso" ]]; then
        mv "${name}.iso" "${final_file}.iso"
        sha512sum "${final_file}.iso" > "${final_file}.iso-${CHKSUM_FILE_SUFFIX}"
        sign_checksum "${final_file}.iso-${CHKSUM_FILE_SUFFIX}"
    fi

    popd > /dev/null
    log "Image '${name}'" "OK!"
}

parallel_fn() {
    # Intended to be used only by GNU Parallel
    . "${SCRIPT_DIR}/../globals.sh"
    . "${SCRIPT_DIR}/../common.sh"
    . "${SCRIPT_DIR}/../config/config.sh"

    create_image "$@"
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
export -f create_image
export -f sign_checksum
export -f parallel_fn
procs=$(nproc --all)
max_jobs=$(( ${procs:=0} > PROCS_PER_IMG ? procs / PROCS_PER_IMG : 1 ))
parallel -j ${max_jobs} parallel_fn <<< "${image_list}"
