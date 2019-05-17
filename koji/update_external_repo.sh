#!/usr/bin/env bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=common.sh

set -e

SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

. "${SCRIPT_DIR}/../common.sh"

KOJI_TAG=${KOJI_TAG:-"dist-clear"}
repo_name="dist-clear-external-repo"
repo_prefix="${CLR_PUBLIC_DL_URL}/releases/"
repo_suffix="/clear/\$arch/os/"

current_version=$(koji list-external-repos --name=${repo_name} --quiet)
current_version=${current_version##*releases/}
current_version=${current_version%%${repo_suffix}}

get_upstream_version

(( CLR_LATEST <= current_version )) && exit 0

koji edit-external-repo --url="${repo_prefix}${CLR_LATEST}${repo_suffix}" ${repo_name}
koji regen-repo "${KOJI_TAG}-build"
