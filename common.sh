#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=globals.sh
# shellcheck source=logging.sh
# shellcheck source=variables.sh

LIB_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")") # Do not override SCRIPT_DIR

. "${LIB_DIR}/globals.sh"
. "${LIB_DIR}/logging.sh"
. "${LIB_DIR}/variables.sh"

assert_dep () {
    command -v "$1" > /dev/null 2>&1 || { error "command '$1' not found"; exit 1; }
}

assert_dir () {
    [[ -d $1 ]] > /dev/null 2>&1 || { error "directory '$1' not found"; exit 1; }
}

assert_file() {
    [[ -f $1 ]] > /dev/null 2>&1 || { error "file '$1' not found"; exit 1; }
}

silentkill () {
    if [ -n "$2" ]; then
        kill "$2" "$1" > /dev/null 2>&1 || true
    else
        kill -KILL "$1" > /dev/null 2>&1 || true
    fi
}

fetch_git_repo() {
    local repo="${1}"
    local dir_name="${2}"

    if (( $# != 2 )); then
        error "'fetch_git_repo' requires 2 arguments!"
        return 1
    fi

    if [[ ! -d "./${dir_name}" ]]; then
        log_line "Cloning..." 1
        git clone --quiet "${repo}" "${dir_name}"
        log_line "OK!" 2
    else
        log_line "Updating..." 1
        git -C "./${dir_name}" fetch --prune -P --quiet origin
        git -C "./${dir_name}" reset --hard --quiet origin/master
        log_line "OK!" 2
    fi

    log_line "$(git -C "./${dir_name}" remote get-url origin) ($(git -C "./${dir_name}" rev-parse --short HEAD))" 1
}

fetch_config_repo() {
    log_line "Config Repository:"

    local REPO_HOST=${CONFIG_REPO_HOST:?"CONFIG_REPO_HOST cannot be Null/Unset"}
    local REPO_NAME=${NAMESPACE:?"NAMESPACE cannot be Null/Unset"}

    fetch_git_repo "${REPO_HOST}${REPO_NAME}" "config"

    pushd ./config > /dev/null
    log_line "Checking for the required file..." 1
    assert_file ./config.sh
    log_line "OK!" 2
    popd > /dev/null

    log_line "Done!" 1
}

get_upstream_version() {
    CLR_LATEST=${CLR_LATEST:-$(curl "${CLR_PUBLIC_DL_URL}/latest")} || true
    if [[ -z "${CLR_LATEST}" ]]; then
        error "Failed to fetch Clear Linux latest version."
        exit 2
    fi

    CLR_FORMAT=$(curl "${CLR_PUBLIC_DL_URL}/update/${CLR_LATEST}/format") || true
    if [[ -z "${CLR_FORMAT}" ]]; then
        error "Failed to fetch Clear Linux latest format."
        exit 2
    fi
}

get_downstream_version() {
    DS_LATEST=$(cat "${STAGING_DIR}/latest" 2>/dev/null) || true
    if [[ -z "${DS_LATEST}" ]]; then
        info "Failed to fetch Downstream latest version. First Mix?"
        DS_FORMAT="${CLR_FORMAT:-1}"
    elif ((${#DS_LATEST} < 4)); then
        error "Downstream Clear Linux version number seems corrupted."
        exit 2
    else
        DS_FORMAT=$(cat "${STAGING_DIR}/update/${DS_LATEST}/format" 2>/dev/null) || true
        if [[ -z "${DS_FORMAT}" ]]; then
            error "Failed to fetch Downstream latest format."
            exit 2
        fi

        DS_UP_VERSION="${DS_LATEST: : -3}"
        DS_DOWN_VERSION="${DS_LATEST: -3}"

        DS_UP_FORMAT=$(curl "${CLR_PUBLIC_DL_URL}/update/${DS_UP_VERSION}/format") || true
        if [[ -z "${DS_UP_FORMAT}" ]]; then
            error "Failed to fetch Downstream latest base format."
            exit 2
        fi
    fi
}

get_latest_versions() {
    get_upstream_version
    get_downstream_version
}

calc_mix_version() {
    # Compute initial next version (ignoring the need for format bumps)
    if [[ -z "${DS_LATEST}" || "${CLR_LATEST}" -gt "${DS_UP_VERSION}" ]]; then
        MIX_VERSION=$((CLR_LATEST * 1000 + MIX_INCREMENT))
    elif [[ "${CLR_LATEST}" -eq "${DS_UP_VERSION}" ]]; then
        MIX_VERSION=$((DS_LATEST + MIX_INCREMENT))
        if [[ "${MIX_VERSION: -3}" -eq 000 ]]; then
            error "Invalid Mix Version" \
                "No more Downstream versions available for this Upstream version!"
            exit 1
        fi
    else
        error "Invalid Mix version" \
            "Next Upstream Version is less than the Previous Upstream!"
        exit 1
    fi

    MIX_UP_VERSION="${MIX_VERSION: : -3}"
    MIX_DOWN_VERSION="${MIX_VERSION: -3}"
}

# =================
# Command Overrides
# =================

curl() {
    command curl --silent --fail "$@"
}

koji_cmd() {
    # Downloads fail sometime, try harder!
    local result=""
    local ret=1
    for (( i=0; i < 10; i++ )); do
        result=$(koji "${@}" 2> /dev/null) \
            || continue

        ret=0
        break
    done

    [[ -n "${result}" ]] && echo "${result}"
    return ${ret}
}

mixer_cmd() {
    # shellcheck disable=SC2086
    mixer ${MIXER_OPTS} "${@}"
}

sudo_mixer_cmd() {
    # shellcheck disable=SC2086
    sudo -E mixer ${MIXER_OPTS} "${@}"
}
