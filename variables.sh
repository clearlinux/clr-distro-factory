#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# ================================================================
# Methodology to easily pass variables among scripts in a pipeline
# ================================================================

# Requires: logging.sh

var_save() {
    local VARS_DIR=${VARS_DIR:?"VARS_DIR Cannot be Null/Unset"}

    if (( $# != 1 )); then
        error "'var_save' requires a single argument!"
        return 1
    fi

    # "unsave"
    if [[ ! -v ${1} ]]; then
        rm -f "${VARS_DIR}/${1}"
        return 0
    fi

    [[ -d ${VARS_DIR} ]] || mkdir -p "${VARS_DIR}"

    echo "${!1}" > "${VARS_DIR}/${1}"
}

var_load() {
    if (( $# != 1 )); then
        error "'var_load' requires a single argument!"
        return 1
    fi

    # shellcheck disable=2015
    [[ -f ${VARS_DIR}/${1} ]] && declare -g "${1}"="$(< "${VARS_DIR}/${1}")" || true
}

var_load_all() {
    [[ ! -d "${VARS_DIR}" ]] && return

    while read -r VAR; do
        declare -g "${VAR}"="$(< "${VARS_DIR}/${VAR}")"
    done <<< "$(ls "${VARS_DIR}")"
}
