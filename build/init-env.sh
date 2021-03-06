#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# CLR_LATEST:      Mix against a specific Upstream version instead of latest
# CLR_BUNDLES:     Subset of bundles to be used from upstream (instead of all)
# DISTRO_BUNDLES:  Subset of bundles to be used from local (instead of all)
# MIN_VERSION:     If this build should be a min version

# shellcheck source=common.sh

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"

# ==============================================================================
# MAIN
# ==============================================================================
stage "Initialization"

log_line "Sanitizing work environment..."
LOG_INDENT=1 fetch_config_repo
. ./config/config.sh

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"/release/{config,images}

mkdir -p "${PKGS_DIR}"

mkdir -p "${MIXER_DIR}"
rm -rf "${MIXER_DIR}/local-yum"
mkdir -p "${MIXER_DIR}/local-yum"

mkdir -p "${STAGING_DIR}"
log_line "OK!" 1

echo "=== Build Environment" > "${WORK_DIR}/${BUILD_FILE}"
tee -a "${WORK_DIR}/${BUILD_FILE}" <<EOL
Workflow Repository:
    $(git remote get-url origin) ($(git rev-parse --short HEAD))
Workflow Config Repository:
    $(git -C config remote get-url origin) ($(git -C config rev-parse --short HEAD))

EOL

section "Configuration"
log "Distribution" "${DISTRO_NAME}"
log "Bundles Repository" "${BUNDLES_REPO}"
log "Distribution URL" "${DISTRO_URL}"
log "Distribution Content URL" "${CONTENT_URL:-"${DISTRO_URL}/update"}"
log "Distribution Version URL" "${VERSION_URL:-"${DISTRO_URL}/update"}"
log "Distribution Koji Server" "${KOJI_URL}"
log "Distribution Koji Tag" "${KOJI_TAG}"
log "Distribution Bundles" "${DISTRO_BUNDLES:-"All"}"
log "Publishing Host" "${PUBLISHING_HOST}"
log "Publishing Root" "${PUBLISHING_ROOT}"
log "Is this an 'downstream' mix?"
if ${IS_DOWNSTREAM}; then
    log_line "Yes!" 1
    log "Upstream URL" "${CLR_PUBLIC_DL_URL}"
    log "Upstream Bundles" "${CLR_BUNDLES:-"All"}"
else
    log_line "No!" 1
fi


section "Signing"
log_line "Custom update signing provided?"
if function_exists sign_update; then
    log_line "Yes!" 1
    cp -f "${SWUPD_CERT:?"SWUPD_CERT Cannot be Null/Unset"}" "${MIXER_DIR}/Swupd_Root.pem"
    log "Swupd cert" "${SWUPD_CERT}"
else
    log_line "No!" 1
fi

log_line "Custom image signing provided?"
if function_exists sign_image; then
    log_line "Yes!" 1
else
    log_line "No!" 1
fi

section "Workspace"
log "Namespace" "${NAMESPACE}"
log "Work dir" "${WORK_DIR}"
log "Variables dir" "${VARS_DIR}"
log "Repository dir" "${REPO_DIR}"
log "Bundles dir" "${BUNDLES_DIR}"
log "Packages dir" "${PKGS_DIR}"
log "Mixer dir" "${MIXER_DIR}"
log "Stage dir" "${STAGING_DIR}"

section "Versions"
if ${IS_DOWNSTREAM}; then
    get_upstream_version
    var_save CLR_FORMAT
    var_save CLR_LATEST
    log "Latest Upstream version (format)" "${CLR_LATEST} (${CLR_FORMAT})"
fi

get_distro_version
var_save DISTRO_FORMAT
var_save DISTRO_LATEST
var_save DISTRO_UP_FORMAT
var_save DISTRO_UP_VERSION
var_save DISTRO_DOWN_VERSION

log "Latest Released version (format)"
if [[ -z ${DISTRO_LATEST} ]]; then
    log_line "This will be the *First* Mix! (1)" 1
else
    log_line "${DISTRO_LATEST} (${DISTRO_FORMAT})" 1
    if ${IS_DOWNSTREAM}; then
        log "Based on Upstream Version" "${DISTRO_UP_VERSION} (${DISTRO_UP_FORMAT})"
    fi
fi
log "Mix Increment" "${MIX_INCREMENT}"

calc_mix_version
var_save MIX_FORMAT
var_save MIX_VERSION
var_save MIX_UP_VERSION
var_save MIX_DOWN_VERSION
log "Next Version" "${MIX_VERSION} (${MIX_FORMAT})"

log "Should this build be a MIN version?"
if ${MIN_VERSION}; then
    log_line "Yes!" 1
else
    log_line "No!" 1
fi

if ! ${IS_DOWNSTREAM}; then
    log "Should this build be a Format Bump?"
    if ${FORMAT_BUMP}; then
        log_line "Yes!" 1
    else
        log_line "No!" 1
    fi
fi

assert_dep mixer
assert_dep clr-installer
assert_dep swupd
assert_dep sha512sum

echo
tee -a "${WORK_DIR}/${BUILD_FILE}" <<EOL
== TOOLS ==
Clear Linux Version (on Builder):
    $(cat /usr/share/clear/version)
Mixer Version:
    $(mixer --version)
Clr-installer Version:
    $(clr-installer --version)
Swupd Version:
    $(swupd --version 2>&1 | head -1)

EOL

mixer_ver_abs=$(mixer --version | sed -E -e 's/([A-Z][a-z]+ )([0-9]+)(.)([0-9]+)(.)([0-9]+)/\2\4\6/')
mixer_ver_min_abs=$(echo "${MIXER_VER_MIN}" | sed -E -e 's/([0-9]+)(.)([0-9]+)(.)([0-9]+)/\1\3\5/')
if (( mixer_ver_abs < mixer_ver_min_abs )); then
    error "Unsupported Mixer Version" "Mixer version needs to be ${MIXER_VER_MIN} or greater"
    error "Aborting build to avoid corrupting your mixer workspace"
    exit 1
fi
