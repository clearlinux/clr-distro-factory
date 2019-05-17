#!/usr/bin/env bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# =================
# Logging Utilities
# =================

# LOG_DOMAIN = Domain name to be printed in the beginning of each log line
# LOG_INDENT = Indentation level to be applied on the log message after 'domain'
#
# To be used with 'run_and_log':
# LOG_DIR    = Directory where log files are saved. Default = '${WORK_DIR}/logs'
# LOG_METHOD = One of the following logging alternatives:
#              0 - Log to file (Default)
#              1 - Log to file and std{out,err}
#              2 - Log to std{out,err}
#            > 2 - Don't log

log_line() {
    # ${1} - log message
    # ${2} - extra indentation

    local indent=${1:+$(( (${LOG_INDENT:-0} + ${2:-0}) * 4 ))}
    printf "${LOG_DOMAIN:+"[${LOG_DOMAIN}] "}%${indent}s%s\\n" "" "${1}"
}

log() {
    # ${1} - log title (or message for single line logs)
    # ${2} - log message (optional)
    # ${3} - extra indentation (optional, requires ${2})

    if (( $# < 2 )); then
        log_line "${1}"
    else
        log_line "${1}:" "${3}"
        log_line "${2}" $((${3:-0} + 1))
    fi
}

stage() {
    log_line "=== ${1^^}"
}

section() {
    log_line
    log_line "== ${1} =="
}

error() {
    log "[ERROR] ${1}" ${2:+"${2}"} "${3}"
}

info() {
    log "[INFO] ${1}" ${2:+"${2}"} "${3}"
}

warn() {
    log "[WARN] ${1}" ${2:+"${2}"} "${3}"
}

run_and_log() {
    if (( $# != 2 )); then
        error "'run_and_log' requires exactly 2 arguments!"
        return 1
    fi

    local cmd=${1}
    local log_out="${2}.log"
    local log_err="${2}_err.log"
    local log_dir=${LOG_DIR:-"./logs"}

    mkdir -p "${log_dir}"

    # Log to file
    if [[ "${LOG_METHOD}" -eq 0 ]]; then
        ${cmd} > "${log_dir}/${log_out}" 2> "${log_dir}/${log_err}" &
    # Log to file and stdout
    elif [[ "${LOG_METHOD}" -eq 1 ]]; then
        ${cmd} > >(tee "${log_dir}/${log_out}") 2> >(tee "${log_dir}/${log_err}") &
    # Log to stdout only
    elif [[ "${LOG_METHOD}" -eq 2 ]]; then
        ${cmd} &
    # No output
    else
        ${cmd} > /dev/null 2> /dev/null &
    fi
}
