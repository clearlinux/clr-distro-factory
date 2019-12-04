#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=common.sh
# shellcheck disable=2162

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"

. ./config/config.sh

var_load DS_DOWN_VERSION
var_load DS_FORMAT
var_load DS_LATEST
var_load DS_UP_VERSION
var_load MIX_VERSION
var_load MIX_UP_VERSION
var_load MIX_DOWN_VERSION

calculate_diffs() {
    local packages_path

    # Collecting package data for old version
    if [[ -n ${DS_LATEST} ]]; then
        packages_path=${STAGING_DIR}/releases/${DS_LATEST}/${PKG_LIST_FILE}-${DS_LATEST}.txt
        assert_file "${packages_path}"

        old_package_list=$(sed -r 's/(.*)-(.*)-/\1\t\2\t/' "${packages_path}")
    else
        old_package_list=""
    fi

    # Collecting package data for new version
    packages_path=${WORK_DIR}/${PKG_LIST_FILE}
    if [[ -f ${packages_path} ]]; then
        new_package_list=$(sed -r 's/(.*)-(.*)-/\1\t\2\t/' "${packages_path}")
    else
        new_package_list=""
    fi

    # calculate added & changed packages
    while read NN VN RN ; do
        found=false
        while read NO VO RO ; do
            if [[ "${NN}" == "${NO}" ]] ; then
                if [[ "${RN}" != "${RO}" ]] || [[ "${VN}" != "${VO}" ]]  ; then
                    pkgs_changed+=$(printf "\\n    %s    %s-%s -> %s-%s" "${NN}" "${VO}" "${RO}" "${VN}" "${RN}")
                fi
                found=true
                break
            fi
        done <<< $old_package_list
        if ! ${found} ; then
            pkgs_added+=$(printf "\\n    %s    %s-%s" "${NN}" "${VN}" "${RN}")
        fi
    done <<< $new_package_list

    # calculate removed packages
    while read NO VO RO ; do
        found=false
        [[ -z ${NO} ]] && continue
        while read NN VN RN ; do
            if [[ "${NO}" == "${NN}" ]] ; then
                found=true
                break
            fi
        done <<< $new_package_list
        if ! ${found} ; then
            pkgs_removed+=$(printf "\\n    %s    %s-%s" "${NO}" "${VO}" "${RO}")
        fi
    done <<< $old_package_list
}

generate_release_notes() {
    calculate_diffs

    local distro_format=$(< "${MIXER_DIR}/update/www/${MIX_VERSION}/format")

    cat > ${RELEASE_NOTES} << EOL
Release Notes for ${MIX_VERSION}

DISTRIBUTION VERSION:
    ${MIX_UP_VERSION} ${MIX_DOWN_VERSION} (${distro_format})

EOL

    if [[ -n ${DS_LATEST} ]]; then
        log "PREVIOUS VERSION" \
            "${DS_UP_VERSION} ${DS_DOWN_VERSION} (${DS_FORMAT})" >> ${RELEASE_NOTES}
        log_line >> ${RELEASE_NOTES}
    fi

    cat >> ${RELEASE_NOTES} << EOL
ADDED PACKAGES:
${pkgs_added:-"    None"}

REMOVED PACKAGES:
${pkgs_removed:-"    None"}

UPDATED PACKAGES:
${pkgs_changed:-"    None"}
EOL
}

# ==============================================================================
# MAIN
# ==============================================================================
pushd "${WORK_DIR}" > /dev/null
log "Generating Release Notes"
generate_release_notes
log_line "Done!" 1
popd > /dev/null
