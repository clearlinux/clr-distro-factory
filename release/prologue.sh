#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# CLR_LATEST:  Mix against a specific Upstream version instead of latest
# CLR_BUNDLES: Subset of bundles to be used from upstream (instead of all)
# DS_BUNDLES:  Subset of bundles to be used from downstream (instead of all)
# MIN_VERSION: If this build should be a min version

# shellcheck source=common.sh

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"

# ==============================================================================
# MAIN
# ==============================================================================
stage "Prologue"
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

cat <<EOL
== Configuration ==
Downstream:
    ${DISTRO_NAME}
Bundles Repository:
    ${BUNDLES_REPO}
Downstream Content/Version URL:
    ${DISTRO_URL}
Downstream Koji Server:
    ${KOJI_URL}
Downstream Koji Tag:
    ${KOJI_TAG}
Dowstream Bundles:
    ${DS_BUNDLES:-"All"}
Upstream URL:
    ${CLR_PUBLIC_DL_URL}
Upstream Bundles:
    ${CLR_BUNDLES:-"All"}
EOL

echo
echo "== Signing =="
echo "Custom update signing provided?"
if function_exists sign_update; then
    echo "    Yes!"
    cp -f "${SWUPD_CERT:?"SWUPD_CERT Cannot be Null/Unset"}" "${MIXER_DIR}/Swupd_Root.pem"
    echo "Swupd cert:"
    echo "    ${SWUPD_CERT}"
else
    echo "    No!"
fi
echo "Custom image signing provided?"
if function_exists sign_image; then
    echo "    Yes!"
else
    echo "    No!"
fi
echo

cat <<EOL
== Workspace ==
Namespace:
    ${NAMESPACE}
Work dir:
    ${WORK_DIR}
Variables dir:
    ${VARS_DIR}
Repository dir:
    ${REPO_DIR}
Bundles dir:
    ${BUNDLES_DIR}
Packages dir:
    ${PKGS_DIR}
Mixer dir:
    ${MIXER_DIR}
Stage dir:
    ${STAGING_DIR}
EOL

section "Versions"

if ${IS_UPSTREAM}; then
    # HACK to get mixer to work with both upstreams and downstreams
    get_upstream_version
    var_save CLR_FORMAT
    var_save CLR_LATEST

    ds_latest_file="${MIXER_DIR}/update/www/version/latest_version"
    if [[ -s "${ds_latest_file}" ]]; then
        DS_LATEST="$(< "${ds_latest_file}")"
        MIX_VERSION=$(( DS_LATEST + MIX_INCREMENT ))
    else
        DS_LATEST=""
        # Needed because mixer init puts mix at version 10, and need to update
        # version to a value greater than 10 for the command to work properly
        MIX_VERSION=$(( 10 + MIX_INCREMENT ))
    fi
    var_save DS_LATEST
    var_save MIX_VERSION

    ds_format_file="${MIXER_DIR}/update/www/${DS_LATEST}/format"
    if [[ -s "${ds_format_file}" ]]; then
        MIX_FORMAT="$(< "${ds_format_file}")"
    else
        # shellcheck disable=SC2034
        MIX_FORMAT=1
    fi
    var_save MIX_FORMAT
else
    get_latest_versions
    var_save CLR_FORMAT
    var_save CLR_LATEST
    var_save DS_DOWN_VERSION
    var_save MIX_FORMAT
    var_save DS_LATEST
    var_save DS_UP_FORMAT
    var_save DS_UP_VERSION

    echo "Latest Upstream version (format):"
    echo "    ${CLR_LATEST} (${CLR_FORMAT})"
    echo "Latest Downstream version (format):"
    if [[ -z ${DS_LATEST} ]]; then
        echo "    First Mix! (0)"
    else
        echo "    ${DS_UP_VERSION} ${DS_DOWN_VERSION} (${MIX_FORMAT})"
        echo "Based on Upstream Version:"
        echo "    ${DS_UP_VERSION} (${DS_UP_FORMAT})"
    fi
    echo "Mix Increment:"
    echo "    ${MIX_INCREMENT}"

    calc_mix_version
    var_save MIX_VERSION
    var_save MIX_UP_VERSION
    var_save MIX_DOWN_VERSION

    echo "Next Downstream Version:"
    echo "    ${MIX_UP_VERSION} ${MIX_DOWN_VERSION} (${MIX_FORMAT})"
fi
echo "Should this build be a MIN version?"
if ${MIN_VERSION}; then
    echo "    Yes!"
else
    echo "    No!"
fi

echo "Is this an 'upstream' mix?"
if ${IS_UPSTREAM}; then
    echo "    Yes!"
else
    echo "    No!"
fi

echo

assert_dep mixer
assert_dep clr-installer
assert_dep swupd
assert_dep sha512sum

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

mixer_major_ver=$(mixer --version | sed -E -e 's/.*([0-9]+).[0-9]+.[0-9]+$/\1/')
if (( mixer_major_ver < MIXER_MAJOR_VER )); then
    error "Unsupported Mixer Version" "Mixer major version needs to be ${MIXER_MAJOR_VER} or greater"
    error "Aborting build to avoid corrupting your mixer workspace"
    exit 1
fi
