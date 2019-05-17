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
# LOG_NAME   = Prefix used for the log file name.
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
    if (( ${#} == 0 )); then
        error "'run_and_log' requires a command!"
        return 1
    fi

    mkdir -p "${LOG_DIR}"

    local log_base="${LOG_DIR}/${LOG_NAME:-${1}}"

    # Log to file
    if [[ "${LOG_METHOD}" -eq 0 ]]; then
        # shellcheck disable=2068
        ${@} > "${log_base}.log" 2> "${log_base}_err.log"
    # Log to file and stdout/stderr
    elif [[ "${LOG_METHOD}" -eq 1 ]]; then
        # shellcheck disable=2068
        ${@} > >(tee "${log_base}.log") 2> >(tee "${log_base}_err.log")
    # Log to stdout/stderr only
    elif [[ "${LOG_METHOD}" -eq 2 ]]; then
        # shellcheck disable=2068
        ${@}
    # No output
    else
        # shellcheck disable=2068
        ${@} &> /dev/null
    fi
}
