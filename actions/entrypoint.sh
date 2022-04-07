#!/usr/bin/env bash
##
## entrypoint.sh for Dockerfile automation with GitHub Workflow Actions
##
## This shell script has been adapated from the original ../build.sh
##
## For building on Linux, outside of docker, the shell sript
## ../entrypoint_local.sh may provide a general top-level
## entry point with a build environment for calling this
## shell script.
##
## Depending on the depth of the git checkout for each dotnet repository,
## the build may require more than 8 GiB of filesystem space on the
## build host. In a rough estimate, the builder flesystem may require up
## to 16 GiB of filesystem space.
##
## Optional environment variables
## - ALL_PROXY (no default value)
##   If provided, this value should denote an HTTP proxy for use
##   by NuGet and wget.
##
## - BUILDER_ROOT (default for the docker environment: /builder)
##   If called from ../entrypoint_local.sh this variable will be
##   set to the directory of the work tree containing this source
##   file
##
## - CACHEDIR (default, cache subdirectory of BUILDER_ROOT)
##   This directory will be used during pre-fetch and installation
##   for a .NET SDK bundle for each repository.
##
## - RUNTIME_ROOT, ASPNETC_ROOT, INSTALLER_ROOT
##   Defaults for the Docker environment: /runtime, /aspnetcore, /installer
##
##   If called from ../entrypoint_local.sh these will each be set
##   to a corresponding subdirectory within a 'build' subdir of this
##   source tree.
##
## Assumptions in entrypoint.sh:
##
## - The cross build will be produced for an x64 architecture, in .NET
##   platforms
##
## - Dependencies include:
##
##   build tools, in the host environment: bash; jq; git; patch; sed;
##     awk; bsdtar; gzip; curl; dotnet; ninja; python; clang
##
##   On Linux: findutils; coreutils
##
##   FreeBSD pkgs (ports) for build dependencies under the cross rootfs:
##    * libunwind	(devel/libunwind)
##    * icu		(devel/libicu)
##    * liburcu		(sysutils/liburcu)
##    * lttng-ust	(sysutils/lttng-ust)
##    * libinotify	(devel/libinotify)
##    * one of: heimdal or krb5, for GSS-API support
##
## - When calling ../entrypoint_local.sh, bmake should be available.
##
##   On FreeBSD hosts, bmake would be used as make(1)
##
##   For any host system, BMAKE may be set in the environment for
##   ../entrypoint_local.sh as to denote the path of usable bmake(1)
##   installation
##
##   This entrypoint.sh does not in itself call bmake(1)
##
## - A .NET 6 or .NET Core runtime of some version should be available
##   on the build host. This .NET installation may serve to provide any
##   .NET tooling for patching and building the dotnet source trees.
##   This .NET installation will be supplemented by each .NET SDK
##   installation that will be created at build time, within each source
##   tree.
##
## - For rebuilds outside of Docker, this shell script does not provide
##   any cleanup actions for the .NET installation in each dotnet source
##   tree. Each .NET installation may be removed by recursively
##   removing the '.dotnet' subdirectory of each dotnet source tree.
##
## - Certain environment variables should be provided, such that
##    may normally be defined under a GitHub Workflow Action.
##
##    Outside of the Docker environment for GitHub Actions, the
##    shell script ../entrypoint_local.sh may provide a top-level
##    entry point for calling this script.
##
## - If any local changes have been produced on any of the runtime,
##   aspnetcore, or installer repositories, those changes wil be stored
##   in a git stash during build. This would include any earlier patches
##   for the build, such as from patches stored in this builder
##   repository.
##
##   For any builds produced outside of Docker, this scripting may result
##   in a substantial number of git stash objects for storing any local
##   changes in each dotnet working tree. The goal with this stage in
##   the scripting was to preserve any local changes, before applying
##   any patches to the upstream repositories. For long-running Git
##   checkouts, any Git stash objects can be removed using git-stash(1)
##   within each local dotnet repository and in each Git submodule
##
## Variables that do not have a default here:
##
##  GITHUB_REPOSITORY
##    e.g under the contrib mirror, thinkum-sys/dotnet-freebsd-crossbuild
##    e.g for the main repository, Thefrank/dotnet-freebsd-crossbuild
##    used only for when this script is run within docker
##
##    When called from ../entrypoint_local.sh GITHUB_REPOSITORY will
##    not be needed, as the BUILDER_ROOT environment variable will
##    have been set to the filesystem pathname of this git work tree
##
##    When called from within a GitHub Workflow action, this variable
##    would have been set to for the repository of the providing Action
##
##  TAG_RUNTIME, TAG_ASPNETC, TAG_INSTALLER
##    When called from ../entrypoint_local.sh these variables will
##    be set from ../versions.mk (bmake)
##
## Known Limitations / TO DO
##
## - This script does not provide any cleanup or monitoring for
##   files created under TMPDIR.
##
##   When called from ../entrypoint_local.sh, by default a local TMPDIR
##   will be used under the builder directory, as <srcroot>/build/tmpdir
##
## - Create a docker image for this entrypoint.sh in some Linux
##   environment.
##
## - Provide a GitHub Workflow/Action script for initializing the build
##   with the corresponding Docker image.
##
## - Add a section to this script for resource packaging and publishing
##   for objects created in this cross build. The published objects
##   should be available for any stages of the build process that may be
##   produced in a FreeBSD environment.
##
## - For calling this script from ../entrypoint_local.sh, add any
##   additional scripting for build dependencies under any single
##   Linux environment

set -e

if [ -n "${DEBUG_BUILD}" ]; then
    set -x
    ## The following environment variables will provide debugging output
    ## from git. In side effects, these may be of some use for git fetch
    ## over unreliable network links.
    export GIT_TRACE_PACKET=1 GIT_TRACE=1 GIT_CURL_VERBOSE=1
fi

## BUILDER_ROOT should indicate a pathname for the Git work tree
## providing this shell script. If no file exists at BUILDER_ROOT,
## then the GITHUB_REPOSITORY will be cloned to the BUILDER_ROOT
## pathname.
##
## This path will be used for patching the upstream sources,
## before the cross build.
: ${BUILDER_ROOT:=/builder}
## RUNTIME_ROOT, ASPNETC_ROOT, and INSTALLER_ROOT should each
## provide the pathname of a working tree for a dotnet repository,
## respectively dotnet/runtime, dotnet/aspnetcore, and dotnet/installer
## repositories at github.com. If these pathames do not exist, then
## git clone will be called to initialize each pathname, before
## git checkout of the version for build in each repository.
: ${RUNTIME_ROOT:=/runtime}
: ${ASPNETC_ROOT:=/aspnet}
: ${INSTALLER_ROOT:=/installer}

: ${TMPDIR:=/tmp}

## ROOTFS_DIR will be used as CROSS_ROOTFS in the cmake section
## when cross-building the dotnet/runtime source tree.
##
## This directory will be populated with a FreeBSD base system,
## installed absent of special file attributes. This will be
## installed for the FreeBSD release denoted in CROSS_RELEASE.
##
## The base.txz image for the release will be fetched from
## CROSS_ORIGIN
##
## FIXME package files should be installed for CROSS_RELEASE
## under the same ROOTFS_DIR
: ${ROOTFS_DIR:=${BUILDER_ROOT}/build/cross}

## NuGet cache dir
: ${CACHEDIR:=${BUILDER_ROOT}/cache}

## URL prefix for .NET SDK distributions
: ${DOTNET_DISTSITE:=https://dotnetcli.azureedge.net/dotnet/Sdk}

## String for OfficialbuildID
##
## This literal value has a specific syntax. The last three characters
## should be of a format "-DD" but the second to last digit should
## not be zero. Keeping with the syntax of ../build.sh, the suffix
## '-99' is used. As a side effect, builds produced on the same day
## in the current timezone will have the same build ID
: ${BUILD_ID:=$(date "+%Y%m%d-99")}

## Base URL for GitHub repositories used in this script.
## normally provided by the GitHub Workflow environment
: ${GITHUB_SERVER_URL:=https://github.com}

## FreeBSD release and origin for the cross-rootfs base system
##
## FIXME CROSS_RELEASE should also be used for cross-rootfs pkg installation
: ${CROSS_RELEASE:=12.3-RELEASE}
: ${CROSS_ORIGIN:=http://ftp.freebsd.org/pub/FreeBSD/releases}


## "clean build" flag; If a non-empty string, each dotnet source tree
## will be cleaned before build. This value is set by default.
##
## As a side effect, in each dotnet source tree before patch:
## - reset local changes
## - remove untracked and ignored files
##
## NuGet packages will be cached external to each source tree
##
: ${CLEAN_BUILD:=defined}

## Kerberos 5 version from FreeBSD ports for cross-rootfs
##
## Accepted values:
##   heimdal => uses pkg for port security/heimdal
##   mit => uses pkg for port security/krb5
##
## FIXME if producing build deps for dotnet suport under ports,
## a separate build should be produced for each supported value here.
## The corresponding krb5 port may then serve as a runtime dependency
## for a port using the cross-build resources produced here.
: ${CROSS_DEP_KRB5:=heimdal}

## common args for the build scripts
COMMON_ARGS=(/p:OfficialBuildId="${BUILD_ID}" -c Release)
if [ -n "${DEBUG_BUILD}" ]; then
    ## FIXME seemingly unused by the internal dotnet scripting, here
    COMMON_ARGS+=(/fileLogger)
    COMMON_ARGS+=(/fileLoggerParameters:Verbosity=diag)
    COMMON_ARGS+=(/fileLoggerParameters:LogFile=build.log)
fi


msg() {
    echo "#-- $@" 1>&2
}
fail() {
    local msg="$1"; shift
    local excode=1
    local exstr=""
    if [ -n "${1:-}" ]; then
        excode="$1"; shift
        exstr=" (${excode})"
    fi
    msg "entrypoint.sh: failed${exstr}: ${msg}"
    exit ${excode}
}

_git_st_rm() {
    ## remove any untracked and ignored files in a Git repository,
    ## with the list of files and dirs to remove provided by
    ## git-status(1)
    local TREE="$1"; shift
    cd "${TREE}"
    git status -uall --ignored=matching --short |
        awk 'BEGIN { ORS="\0" } $1 == "??" || $1 == "!!" { print $2 }' |
        xargs -0 rm -rf
}

## export for use in git-submodule(1)
export -f _git_st_rm

update_tree() {
    ## utility function for eval outside of docker
    local TREE="$1"; shift
    local TAG="$1"; shift
    local HERE="${PWD}"
    cd "${TREE}"

    if [ -e "${TREE}" ]; then
        ## tree already exists - probably not running under docker.
        ##
        ## this will use local build/${TAG} branches for differentiating
        ## tag names to branch names
        msg "Source tree already exists, updating for tag ${TREE} => ${TAG}"
        if git rev-parse build/${TAG} &>/dev/null; then
            ## stash any earlier changes, to undo any patches
            ## that will be applied below
            git switch build/${TAG}
        elif git rev-parse ${TAG} &>/dev/null; then
            git switch -c build/${TAG} ${TAG}
        else
            ## use the first defined origin to automate fetch
            local ORIGIN=$(git remote | head -n1)
            git fetch --tags --depth=1 ${ORIGIN} ${TAG}
            git checkout ${TAG}
            git switch -c build/${TAG} ${TAG}
            git submodule init
            git submodule foreach --recursive \
                'git submodule init; git submodule update'
        fi
        if [ -n "${CLEAN_BUILD:-}" ]; then
            msg "Cleaning ${TREE}"
            _git_st_rm "${TREE}"
            local FUNCS="$(export -fp)"
            git submodule foreach "bash -c \"${FUNCS}; _git_st_rm \$toplevel\""
            git reset --hard
            git submodule foreach --recursive 'git reset --hard'
        fi
    else
        git clone --depth 1 --tags $@
        git switch -c build/${TAG} ${TAG}
    fi
    cd "${HERE}"
}

format_sdk_file() {
    local VERS="$1"; shift
    local RST="${1:-}"
    printf 'dotnet-sdk-%s-linux-x64.tar.gz%s' "${VERS}" "${RST}"
}

format_sdk_url() {
    local SITE="${1%/}"; shift
    local VERS="$1"; shift
    local RST="${1:-}"
    local F=$(format_sdk_file "${VERS}" "${RST}")
    printf '%s/%s/%s%s' "${SITE}" "${VERS}" "${F}"
}


fetch_dotnet() {
    local TREE="$1"; shift
    local VERS=$(jq '.sdk.version' ${TREE}/global.json | sed 's@"@@'g)
    local SDK=$(format_sdk_file "${VERS}")
    local SDKWEB=$(format_sdk_url "${DOTNET_DISTSITE}" "${VERS}")

    if ! [ -e "${CACHEDIR}/${SDK}" ]; then
        curl -o "${CACHEDIR}/${SDK}" "${CURL_ARGS}" "${SDKWEB}"
    fi

    gzip --test  "${CACHEDIR}/${SDK}" ||
        fail "SDK archive failed check: ${CACHEDIR}/${SDK}" $?
    mkdir -p ${TREE}/.dotnet
    bsdtar -C ${TREE}/.dotnet -xzf "${CACHEDIR}/${SDK}"
}

patch_tree() {
    ## using GNU patch, with a backup file option
    ## TBD creating an update_patches function for local builds
    local DST="$1"; shift
    local PATCH="$1"; shift
    local HERE="${PWD}"
    cd "${DST}"
    git stash push -m "changes before ${BUILD_ID}" || true
    patch -p1 --backup --suffix=.orig --batch < ${PATCH}
    cd "${HERE}"
}

patch_nuget() {
    ## from ../build.sh
    local DST="$1"; shift
    sed -i.bak '/\/dnceng\/internal\//d' ${DST}/NuGet.config
}

build_tree() {
    local TREE="$1"; shift
    local HERE="${PWD}"
    cd "${TREE}"
    env "${BUILDER_ENV[@]}" DOTNET_INSTALL_DIR=${TREE}/.dotnet \
        DOTNET_ROOT=${TREE}/.dotnet ${TREE}/build.sh "${COMMON_ARGS[@]}" \
        "$@" || fail "Build failed for ${TREE}" $?
    cd "${HERE}"
}


## dependencies for cross-rootfs in dotnet/runtime
CROSS_DEPS=(libunwind icu lttng-ust liburcu libinotify)
case ${CROSS_DEP_KRB5} in
    heimdal)
        CROSS_DEPS+=heimdal
        ;;
    mit)
        CROSS_DEPS+=krb5
        ;;
    *)
        fail "Unkonwn CROSS_DEP_KRB5: ${CROSS_DEP_KRB5}"
        ;;
esac



## tags for automated git checkout/switch
if [ -z "${TAG_RUNTIME:-}" ]; then
    fail "TAG_RUNTIME not provided"
elif [ -z "${TAG_ASPNETC:-}" ]; then
    fail "TAG_ASPNETC not provided"
elif [ -z "${TAG_INSTALLER:-}" ]; then
    fail "TAG_INSTALLER not provided"
fi

if [ -n "${GITHUB_REF:-}" ]; then
    ## provided in the GitHub Workflow environment,
    ## when a reference is avaialble for this repository
    BUILDER_REF="--branch ${GITHUB_REF}"
fi

if [ -e "${BUILDER_ROOT}" ]; then
    ## do not update the source tree under BUILDER_ROOT
    msg "builder root already available, skipping clone: ${BUILDER_ROOT}"
else
    ## clone the repository for the GitHub Workflow, under docker
    git clone --depth 1 ${BUILDER_REF} \
        ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}.git ${BUILDER_ROOT}
fi

if [ -n "${GITHUB_SHA:-}" ]; then
    ## Docker environment
    ## if GITHUB_SHA is defined, use this as a head changeset for patches
    git checkout ${GITHUB_SHA} ${BUILDER_ROOT}
    cd ${BUILDER_ROOT}
fi

## clone and patch the dotnet runtime repository
update_tree ${RUNTIME_ROOT} ${TAG_RUNTIME} \
            ${GITHUB_SERVER_URL}/dotnet/runtime.git
patch_tree ${RUNTIME_ROOT} ${BUILDER_ROOT}/patches/patch_runtimeRTM.patch
patch_tree ${RUNTIME_ROOT} ${BUILDER_ROOT}/patches/patch_runtimeTBD.patch
patch_nuget ${RUNTIME_ROOT}

## clone and patch the dotnet AspNetCore repository
update_tree ${ASPNETC_ROOT} ${TAG_ASPNETC} \
            ${GITHUB_SERVER_URL}/dotnet/aspnetcore.git --recursive
patch_tree  ${ASPNETC_ROOT} ${BUILDER_ROOT}/patches/patch_aspnetcoreRTM.patch
patch_nuget ${ASPNETC_ROOT}

## clone and patch the dotnet installer repository
update_tree ${INSTALLER_ROOT} ${TAG_INSTALLER} \
            ${GITHUB_SERVER_URL}/dotnet/installer.git
patch_tree ${INSTALLER_ROOT} ${BUILDER_ROOT}/patches/patch_installerRTM.patch
patch_nuget ${INSTALLER_ROOT}

mkdir -p ${TMPDIR} ${ROOTFS_DIR} ${CACHEDIR}/nupkg

## fetch and install each dotnet SDK bundle
fetch_dotnet "${RUNTIME_ROOT}"
fetch_dotnet "${ASPNETC_ROOT}"

## fetch and install the cross rootfs
if ! [ -e "${ROOTFS_DIR}/bin/freebsd-version" ]; then
    ## FIXME no clean option here other than to remove ROOTFS_DIR
    ## external to this script
    msg "Fetching cross base system (${CROSS_RELEASE}) from ${CROSS_ORIGIN}"
    wget -O "${CACHEDIR}/base.txz" -c ${WGET_ARGS} \
         "${CROSS_ORIGIN}/amd64/${CROSS_RELEASE}/base.txz"
    msg "Extracing cross base system (${CROSS_RELEASE}) to ${ROOTFS_DIR}"
    bsdtar --no-fflags -C ${ROOTFS_DIR} -Jx -f ${CACHEDIR}/base.txz
fi

BUILDER_ENV=(ROOTFS_DIR="${ROOTFS_DIR}" TMPDIR="${TMPDIR}")
BUILDER_ENV+=(NUGET_PACKAGES="${CACHEDIR}/nupkg")

if [ -n "${ALL_PROXY}" ]; then
    ## proxy environment for curl
    BUILDER_ENV+=(ALL_PROXY="${ALL_PROXY}")
    ## proxy environment for wget
    BUILDER_ENV+=(http_proxy="${ALL_PROXY}")
    BUILDER_ENV+=(https_proxy="${ALL_PROXY}")
    BUILDER_ENV+=(ftp_proxy="${ALL_PROXY}")
fi

## enable retry in nuget
##
## other flags:
## NUGET_ENHANCED_MAX_NETWORK_TRY_COUNT
## NUGET_ENHANCED_NETWORK_RETRY_DELAY_MILLISECONDS
## via
## https://docs.microsoft.com/en-us/nuget/reference/cli-reference/cli-ref-environment-variables
BUILDER_ENV+=(NUGET_ENABLE_ENHANCED_HTTP_RETRY=true)

## build the runtime repository
build_tree ${RUNTIME_ROOT} \
           -ninja -cross -os freebsd

## see ../build.sh
dotnet nuget add source ${RUNTIME_ROOT}/artifacts/packages/Release/Shipping \
    --name runtime --configfile ${ASPNETC_ROOT}/NuGet.config
mkdir -pv ${ASPNETC_ROOT}/artifacts/obj/Microsoft.AspNetCore.App.Runtime
cp -pv \
    ${RUNTIME_ROOT}/artifacts/packages/Release/Shipping/dotnet-runtime-*-freebsd-x64.tar.gz \
    ${ASPNETC_ROOT}/artifacts/obj/Microsoft.AspNetCore.App.Runtime

## build the AspNetCore repository
build_tree ${ASPNETC_ROOT} \
           --os-name freebsd -pack /p:CrossgenOutput=false

## see ../build.sh
dotnet nuget remove source msbuild \
      --configfile ${INSTALLER_ROOT}/NuGet.config || true
dotnet nuget remove source nuget-build \
      --configfile ${INSTALLER_ROOT}/NuGet.config || true
dotnet nuget add source ${RUNTIME_ROOT}/artifacts/packages/Release/Shipping \
      --name runtime --configfile ${INSTALLER_ROOT}/NuGet.config || true
dotnet nuget add source ${ASPNETC_ROOT}/artifacts/packages/Release/Shipping
      --name aspnetcore --configfile ${INSTALLER_ROOT}/NuGet.config || true

mkdir -p ${INSTALLER_ROOT}/artifacts/obj/redist/Release/downloads/
cp -pv \
    ${RUNTIME_ROOT}/artifacts/packages/Release/Shipping/dotnet-runtime-*-freebsd-x64.tar.gz \
    ${INSTALLER_ROOT}/artifacts/obj/redist/Release/downloads/
cp -pv \
    ${ASPNETC_ROOT}/artifacts/installers/Release/aspnetcore-runtime-* \
    ${INSTALLER_ROOT}/artifacts/obj/redist/Release/downloads/

## build the installer repository
build_tree "${INSTALLER_ROOT}" \
           -pack --runtime-id freebsd-x64 \
           /p:OSName=freebsd /p:CrossgenOutput=false \
           /p:IncludeAspNetCoreRuntime=True /p:DISABLE_CROSSGEN=True

## FIXME package the files for availability in some FreeBSD port build
