#!/usr/bin/env bash
#
# local scripting for running actions/entrypoint.sh outside of Docker
#
# entrypoint.sh is designed to be run in a Linux environment
#

set -e

if [ -n "${DEBUG_BUILD:-}" ]; then
    set -x
fi

if [ -z "${BMAKE:-}" ]; then
    case $(uname -s) in
        FreeBSD)
            BMAKE=make
            ;;
        *)
            BMAKE=bmake
            ;;
    esac
fi

THIS=$(readlink -f "$0")
HERE=$(dirname "${THIS}")

get_tag() {
    local TREE=$1; shift
    ${BMAKE} -f ${HERE}/versions.mk \
            -V "TAG_${TREE}" \
            .MAKE.EXPAND_VARIABLES=true
}

: ${RUNTIME_ROOT:=${HERE}/build/runtime}
: ${ASPNETCORE_ROOT:=${HERE}/build/aspnetcore}
: ${INSTALLER_ROOT:=${HERE}/build/installer}
: ${TMPDIR:=${HERE}/build/tmpdir}

: ${TAG_RUNTIME:=$(get_tag RUNTIME)}
: ${TAG_ASPNETCORE:=$(get_tag ASPNETCORE)}
: ${TAG_INSTALLER:=$(get_tag INSTALLER)}

: ${CROSS_RELEASE:=12.3-RELEASE}
: ${ROOTFS_DIR:=${HERE}/build/cross}

## BULD_PROJECT - list of projects to build
## Default is all
##
## If any value other than default is used,
## then for every preceding project in this list,
## some files should be available at a pathname
## used in the script ./actions/entrypoint.sh
## with the function 'sync_bundles'
##
## This may serve to provide at least a modicum
## of reentrancy for builds under this tooling
: ${BUILD_PROJECTS:="runtime aspnetcore installer"}

RUN_ENV=(BUILD_PROJECTS="${BUILD_PROJECTS}" DEBUG_BUILD="${DEBUG_BUILD}")

RUN_ENV+=(BUILDER_ROOT="${HERE}")
RUN_ENV+=(RUNTIME_ROOT="${RUNTIME_ROOT}")
RUN_ENV+=(ASPNETCORE_ROOT="${ASPNETCORE_ROOT}")
RUN_ENV+=(INSTALLER_ROOT="${INSTALLER_ROOT}")
RUN_ENV+=(TMPDIR="${TMPDIR}")
RUN_ENV+=(TAG_RUNTIME="${TAG_RUNTIME}")
RUN_ENV+=(TAG_ASPNETCORE="${TAG_ASPNETCORE}")
RUN_ENV+=(TAG_INSTALLER="${TAG_INSTALLER}")

if [ -n "${ALL_PROXY}" ]; then
    ## proxy environment for curl
    RUN_ENV+=(ALL_PROXY="${ALL_PROXY}")
    ## proxy environment for wget
    RUN_ENV+=(http_proxy="${ALL_PROXY}")
    RUN_ENV+=(https_proxy="${ALL_PROXY}")
    RUN_ENV+=(ftp_proxy="${ALL_PROXY}")
fi

exec env "${RUN_ENV[@]}" ${SHELL} ${HERE}/actions/entrypoint.sh
