#!/usr/bin/env bash
##
## entrypoint.sh for Dockerfile automation with GitHub Workflow Actions
##
## This shell script has been adapated from the original ../build.sh
##
## For building on Linux, outside of docker, the shell sript
## ../entrypoint_local.sh may provide a general top-level
## entry point, adding some additional configuration of the build
## environment in a call to this shell script
##
## The builder flesystem may require approx. 16 GiB of filesystem space
## for the build
##
## Optional environment variables for build
##
## - CLEAN_BUILD
##   If a non-empty string (default) each dotnet source tree will
##   be removed of all; untracked and ignored files. The repository
##   will then be reset to its head revision, before build.
##
## - DEBUG_BUILD
##   If a non-empty string, this shell script will produce debugging
##   output from bash 'set -x' and from git
##
## - ALL_PROXY (no default value)
##   If provided, this value should denote an HTTP proxy for use
##   by NuGet and curl
##
## - BUILDER_ROOT (default for the docker environment: /builder)
##   If called from ../entrypoint_local.sh this variable will be
##   set to the directory of the work tree containing this source
##   file
##
## - CACHEDIR (default, cache subdirectory of BUILDER_ROOT)
##   This directory will be used during a pre-fetch and installation
##   process for each .NET SDK and .NET runtime bundle that will be used
##   in the build
##
## - RUNTIME_ROOT, ASPNETCORE_ROOT, INSTALLER_ROOT
##   Defaults for the Docker environment: /runtime, /aspnetcore, /installer
##
##   If called from ../entrypoint_local.sh these will each be set
##   to a corresponding subdirectory within a 'build' subdir of this
##   source tree.
##
## Assumptions in entrypoint.sh:
##
## - The cross build will be produced for an x64 architecture in .NET
##   platforms
##
## - Dependencies include:
##
##   build tools, in the host environment: bash; jq; git; patch; sed;
##     awk; bsdtar; gzip; curl; dotnet; cmake; ninja; python; clang
##
##     node.js should be installed before the asponetcore build
##
##     node.js 17 as available in openSUSE: nodejs17 and nodejs17-devel
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
##   FIXME at this point, the build dependencies must be manually
##   installed to the cross rootfs.
##
##   These build dependencies will represent library dependencies for
##   the artifacts built for FreeBSD.
##
##   node.js may represent an additional runtime dependency for the
##   aspnetcore runtime
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
##
##   This host's .NET installation will be supplemented by each .NET SDK
##   installation that will be produced at build time, in the .dotnet
##   subdirectory of each source tree.
##
## - Certain environment variables should be provided, such that
##    may normally be defined under a GitHub Workflow Action.
##
##    Outside of the Docker environment for GitHub Actions, the
##    shell script ../entrypoint_local.sh may provide a top-level
##    entry point for calling this script.
##
## - If any local changes have been produced on any of the runtime,
##   aspnetcore, or installer repositories and CLEAN_BUILD is an empty
##   string, the changes wil be stored in a git stash during build.
##
##   This would include any earlier patches for the build, such as from
##   patches stored in this builder repository.
##
##   If CLEAN_BUILD is a non-empty string, any local changes will be
##   discarded in each dotnet repository.
##
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
##  TAG_RUNTIME, TAG_ASPNETCORE, TAG_INSTALLER
##    When called from ../entrypoint_local.sh these variables will
##    be set from ../versions.mk (bmake)
##
## Known Limitations / TO DO
##
## - This script does not provide any tooling for ccache support,
##   such that could be facilitated at least in ../entrypoint_local.sh
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
## RUNTIME_ROOT, ASPNETCORE_ROOT, and INSTALLER_ROOT should each
## provide the pathname of a working tree for a dotnet repository,
## respectively dotnet/runtime, dotnet/aspnetcore, and dotnet/installer
## repositories at github.com. If these pathames do not exist, then
## git clone will be called to initialize each pathname, before
## git checkout of the version for build in each repository.
: ${RUNTIME_ROOT:=/runtime}
: ${ASPNETCORE_ROOT:=/aspnetcore}
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
## See also: CROSS_DEP_KRB5
##
## ROOTFS_DIR will not be automatically cleaned on rebuild
: ${ROOTFS_DIR:=${BUILDER_ROOT}/build/cross}

## FreeBSD release and origin for the cross-rootfs base system
##
## FIXME CROSS_RELEASE should also be used for cross-rootfs pkg
## installation, with a pkg source repository to be denoted here
##
## FIXME no pkg scripting has been provided in this version.
## FIXME The cross-rootfs build dependencies must be installed
## to the cross-rootfs, external to this script.
##
: ${CROSS_RELEASE:=12.3-RELEASE}
: ${CROSS_ORIGIN:=http://ftp.freebsd.org/pub/FreeBSD/releases}

## Base directory for cached files (dotnet bundles, NuGet, other)
##
## CACHEDIR will not be automatically cleaned on rebuild
: ${CACHEDIR:=${BUILDER_ROOT}/cache}

## URL prefixes for .NET SDK and .NET runtime distributions
: ${SDK_DISTSITE:=https://dotnetcli.azureedge.net/dotnet/Sdk}
: ${RUNTIME_DISTSITE:=https://dotnetcli.azureedge.net/dotnet/Runtime/}
: ${ASPNET_DISTSITE:=https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime}

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

## "clean build" flag; If a non-empty string, each dotnet source tree
## will be cleaned before build. This value is set by default.
##
## As a side effect, then in each dotnet source tree before patch:
## - local changes will be reset
## - untracked and ignored files will be removed
##
## NuGet packages will be cached external to each source tree
##
: ${CLEAN_BUILD:=defined}

## Kerberos 5 version from FreeBSD ports for cross-rootfs
##
## Accepted values:
##   heimdal => install a pkg for the port security/heimdal
##   mit => install a pkg for the port port security/krb5
##   "" the emtpy string => install none. This is the default.
##
## This option is further discussed below, at the usage of this
## variable. The default value may typically not be acceptable
## for the build, unless CROSS_ORIGIN is set to some URL providing
## a base.txz build with support for GSS-API and Kerberos 5. That
## distribution should match the site used for the pkg builds in
## the cross-rootfs build dependencies, or at least provide a
## distribution under a compatible FreeBSD release version.
##
## FIXME if producing build deps for dotnet suport under ports,
## a separate build should be produced for each supported, non-empty
## value here. The corresponding krb5 port may then serve as a runtime
## dependency for any port produced directly from the dotnet/runtime
## cross build produed here.
: ${CROSS_DEP_KRB5:=}

## common args for the build scripts
COMMON_ARGS=(/p:OfficialBuildId="${BUILD_ID}" -c Release)

## try to prevent the compiler from trying and failing to connect to
## a compiler server, when cross-building with linuxulator on FreeBSD
## (it will cause the build to fail)
## FIXME none of this serves to disable it
## ?? /shared compiler arg (how to disable?)
## how to deactivate it in Microsoft.Build.Tasks.CodeAnalysis ?
## https://github.com/dotnet/roslyn/blob/master/docs/compilers/Compiler%20Server.mda
# COMMON_ARGS+=(/p:UseRoslynAnalyzers=false /p:RunAnalyzers=false /p:RunCodeAnalysis=false /m:q)

if [ -n "${DEBUG_BUILD}" ]; then
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
        msg "Source tree already exists: ${TREE}"

        if [ -n "${CLEAN_BUILD:-}" ]; then
            msg "Cleaning ${TREE}"
            git clean -fqx
            git submodule foreach --recursive 'git clean -fqx'
            git reset --hard
            git submodule foreach --recursive 'git reset --hard'
        fi
        msg "Updating for ${TAG} => branch/${TAG} in ${TREE}"
        if git rev-parse build/${TAG} &>/dev/null; then
            if [ -z "${CLEAN_BUILD:-}" ]; then
                msg "Storing local changes in ${TREE}"
                git stash push -m "changes before ${BUILD_ID}" || true
            fi
            git switch build/${TAG}
        elif git rev-parse ${TAG} &>/dev/null; then
            git switch -c build/${TAG} ${TAG}
        else
            local ORIGIN=$(git remote | head -n1)
            ## using the first defined origin to automate fetch
            msg "Updating to ${TAG} in ${TREE}"
            git fetch --tags --depth=1 ${ORIGIN} ${TAG}
            git checkout ${TAG}
            git switch -c build/${TAG} ${TAG}
            git submodule init
            git submodule foreach --recursive \
                'git submodule init; git submodule update'
        fi
    else
        git clone --depth 1 --tags $@
        git switch -c build/${TAG} ${TAG}
    fi
    cd "${HERE}"
}

format_sdk_file() {
    local VERS="$1"; shift
    printf 'dotnet-sdk-%s-linux-x64.tar.gz' "${VERS}"
}

format_sdk_url() {
    local SITE="${SDK_DISTSITE%/}"
    local VERS="$1"; shift
    local F=$(format_sdk_file "${VERS}")
    printf '%s/%s/%s' "${SITE}" "${VERS}" "${F}"
}

format_runtime_file() {
    local VERS="${1}"; shift
    ## in each of these functions, FMWK would be
    ## one of 'dotnet' or 'aspnetcore'
    local FMWRK="${1}"; shift

    if [[ "${VERS}" =~ "-" ]]; then
        VERS="${VERS%-*}"
    fi
    printf '%s-runtime-%s-linux-x64.tar.gz' "${FMWRK}" "${VERS}"
}

format_runtime_url() {
    local QAVERS="${1}"; shift
    local SITE="${1%/}"; shift
    local FMWRK="${1}"; shift

    local VERS="${QAVERS}"
    if [[ "${VERS}" =~ "-" ]]; then
        VERS="${VERS%-*}"
    fi
    local F=$(format_runtime_file "${VERS}" "${FMWRK}")
    printf '%s/%s/%s' "${SITE}" "${QAVERS}" "${F}"
}


check_archive() {
    local F="$1"; shift
    case ${F##*.} in
        gz)
            ## test for dotnet SDK/runtime bundles
            gzip --test "${F}" &>/dev/null
            ;;
        xz|pkg|txz)
            ## test for FreeBSD build dep packages
            xz --test "${F}" &>/dev/null
            ;;
        *)
            ## other (pass)
            ;;
    esac
}

install_dep() {
    local ORG="${1}"; shift
    local DST="${1}"; shift
    local TREE="${1}"; shift
    local F
    if [ -n "${1:-}" ]; then
        F="$1"; shift
    else
        F=$(basename "${ORG}")
    fi

    if [ -e "${CACHEDIR}/${F}" ] &&
           ! check_archive "${CACHEDIR}/${F}"; then
        rm "${CACHEDIR}/${F}"
    fi
    if ! [ -e "${CACHEDIR}/${F}" ]; then
        curl -o "${CACHEDIR}/${F}" ${CURL_ARGS} "${ORG}"
    fi

    ## FIXME this may be difficult to parse from the debug output
    ## produced under bash 'set -x', as when DEBUG_BUILD
    check_archive  "${CACHEDIR}/${F}" ||
        fail "File failed archive check: ${CACHEDIR}/${F}" $?

    bsdtar -C ${TREE}/.dotnet -xzf "${CACHEDIR}/${F}"
}

install_sdk() {
    local TREE="${1}"; shift
    ## this assumes that the sdk version is stored in each global.json
    ## as a literal expression, with no variable substitution
    local SDKVERS=$(jq '.sdk.version | select(. != null)' ${TREE}/global.json |
                        sed 's@"@@'g)
    local NETVERS=$(jq '.tools.dotnet | select(. != null)' ${TREE}/global.json |
                        sed 's@"@@'g)
    local SDK SDKWEB

    mkdir -p ${TREE}/.dotnet

    if [ -n "${SDKVERS}" ]; then
        SDK=$(format_sdk_file "${SDKVERS}")
        SDKWEB=$(format_sdk_url "${SDKVERS}")
        msg "Installing dotnet SDK @ ${SDKVERS} => ${TREE}/.dotnet"
        install_dep "${SDKWEB}" "${SDK}" "${TREE}"
    fi
    if [ -n "${NETVERS}" ] && [ "${NETVERS}" != "${SDKVERS}" ]; then
        SDK=$(format_sdk_file "${NETVERS}")
        SDKWEB=$(format_sdk_url "${NETVERS}")
        msg "Installing dotnet SDK @ ${NETVERS} => ${TREE}/.dotnet"
        install_dep "${SDKWEB}" "${SDK}" "${TREE}"
    fi
}

get_runtime_version() {
    local TREE="${1}"; shift
    local FMWRK="${1:-dotnet}"
    local ARCHVERS=$(jq --arg "KIND" "${FMWRK}" \
                       '.tools.runtimes | getpath([$KIND + "/x64"]) | if . then join(" ") else "" end' \
                       ${TREE}/global.json | sed 's@"@@'g)
    local NETVERS=$(jq --arg "KIND" "${FMWRK}" \
                       '.tools.runtimes | getpath([$KIND]) | if . then join(" ") else "" end' \
                       ${TREE}/global.json | sed 's@"@@'g)
    local USEVERS VERS SUB

    for VERS in ${ARCHVERS} ${NETVERS}; do
        if [[ "${VERS}" =~ '$' ]]; then
            ## VERS is an expression in '$(Property)' form
            ##
            ## parse from ${TREE}/eng/Versions.props
            ## with simple variable substitution (non-recursive)
            SUB="${VERS#$\(}"
            SUB="${SUB%)}"
            ## This retrieves the value of a named property P in
            ## <Project><PropertyGroup><${P}>value</${P}>...
            ## from Version.props XML.
            ##
            ## This can parse each property defined with a literal value.
            ## Ideally, the first iteration for variable substitution may
            ## be sufficient when parsing a global.json for the
            ## projects being built here
            ##
            ## xq will translate the XML to JSON
            VERS=$(xq '.Project.PropertyGroup | .[]' ${TREE}/eng/Versions.props |
                       jq --arg "P" "${SUB}" \
                          'getpath([$P]) | select(. != null)' |
                       sed 's@"@@'g)
        fi
        USEVERS+="${USEVERS:+ }${VERS}"
    done
    echo "${USEVERS}"
}

install_runtime() {
    local TREE="${1}"; shift
    local SITE="${1}"; shift
    local FMWRK="${1:-dotnet}"

    local RVERS=$(get_runtime_version "${TREE}" "${FMWRK}")
    local VERS
    for VERS in ${RVERS}; do
        local RUNFILE=$(format_runtime_file "${VERS}" "${FMWRK}")
        local RUNWEB=$(format_runtime_url "${VERS}" "${SITE}" "${FMWRK}")
        msg "Installing ${FMWRK} runtime @ ${VERS} => ${TREE}/.dotnet"
        install_dep "${RUNWEB}" "${RUNFILE}" "${TREE}"
    done
}

fetch_dotnet() {
    local TREE="$1"; shift
    ##
    ## fetch and install dotnet sdk, if defined in tree's global.json
    ##
    install_sdk "${TREE}"

    ##
    ## fetch and install dotnet and aspnetcore runtimes
    ## if defined in tree's global.json
    ##
    install_runtime "${TREE}" "${RUNTIME_DISTSITE}" dotnet
    install_runtime "${TREE}" "${ASPNET_DISTSITE}" aspnetcore

}

patch_tree() {
    ## using GNU patch, with a backup file option
    ##
    ## the repository will have been reset earlier, in update_tree
    local DST="$1"; shift
    local PATCH="$1"; shift
    local HERE="${PWD}"
    cd "${DST}"
    patch -p1 --backup --suffix=.orig --batch < ${PATCH}
    cd "${HERE}"
}

trim_nuget_internals() {
    ## trim internal channels from NuGet.config
    local DST="$1"; shift
    sed -i.bak '/\/dnceng\/internal\//d' ${DST}/NuGet.config
}

nuget_source_rem() {
    local WHICH="$1"; shift
    local WHENCE="$1"; shift
    ${WHENCE}/.dotnet/dotnet nuget remove source "${WHICH}" \
             --configfile ${WHENXCE}/NuGet.config 2>&1 1>/dev/null || true
}

nuget_source_add() {
    local NAME="$1"; shift
    local FROM="$1"; shift
    local WHENCE="$1"; shift
    ${WHENCE}/.dotnet/dotnet nuget add source --name runtime \
             --configfile ${WHENCE}/NuGet.config \
             ${FROM} 2>&1 1>/dev/null || true
}

init_tree() {
    local TREE="$1"; shift
    local proj=$(basename "${TREE}")
    local TAG="$1"; shift
    msg "Initialize ${proj} working tree @ ${TAG} => ${TREE}"
    update_tree ${TREE} ${TAG} \
                ${GITHUB_SERVER_URL}/dotnet/${proj}.git
    patch_tree ${TREE} ${BUILDER_ROOT}/patches/patch_${proj}RTM.patch
    trim_nuget_internals ${TREE}
}

build_tree() {
    local TREE="$1"; shift
    local HERE="${PWD}"
    local BUILD_SH="${TREE}/build.sh"
    cd "${TREE}"
    if ! [ -s "${BUILD_SH}" ]; then
        ## the source tree does not have a top-level build.sh
        ## e.g AspNetCore v6.0.3
        BUILD_SH=${TREE}/eng/build.sh
    fi
    msg "Building with ${BUILD_SH}"
    env "${BUILDER_ENV[@]}" DOTNET_INSTALL_DIR=${TREE}/.dotnet \
        DOTNET_ROOT=${TREE}/.dotnet ${BUILD_SH} "${COMMON_ARGS[@]}" \
        "$@" || fail "Build failed for ${TREE}" $?
    msg "Build completed in ${TREE}"
    cd "${HERE}"
}


## conditional build - set TO_BUILD scalar array from BUILD_PROJECTS
##
## strings for BUILD_PROJECTS:
##  runtime
##  aspnetcore
##  installer
unset TO_BUILD
declare -A TO_BUILD
for T in ${BUILD_PROJECTS}; do
    TO_BUILD["${T}"]="${T}"
done

building_runtime() {
    test -n "${TO_BUILD[runtime]:-}"
}

building_aspnetcore() {
    test -n "${TO_BUILD[aspnetcore]:-}"
}

building_installer() {
    test -n "${TO_BUILD[installer]:-}"
}


## defining stat_dev. This is a workaround for quirks in portability of
## stat(1) towards hard-linking files when on the same filesystem, or
## copy when not

case $(uname -s) in
     Linux)
         stat_dev() {
             local F="${1}"; shift
             stat -c '%D' "${F}"
         }
         ;;
     *BSD)
         ## FreeBSD, NetBSD
         stat_dev() {
             local F="${1}"; shift
             stat -f '%d' "${F}"
         }
         ;;
     *)
         fail "stat_dev function not implemented on $(uname -s)"
         ;;
esac

sync_runtime_build() {
    local FMWRK="$1"; shift
    local DISTDIR="$1"; shift
    local RCV="$1"; shift
    local XFER="cp -pf"
    local DISTFILE
    if [ -e "${DISTDIR}" ]; then
        mkdir -p "${RCV}"
        if [ $(stat_dev "${DISTDIR}") = $(stat_dev "${RCV}") ]; then
            XFER="ln -f"
        fi
        msg "Installing artifacts for ${DISTDIR} => ${RCV}"
        find ${DISTDIR} -type f -name "${FMWRK}-runtime-*" | {
            while read DISTFILE; do
                ${XFER} "${DISTFILE}" "${RCV}/$(basename "${DISTFILE}")"
            done
        }
    else
        fail "No artifacts found in ${DISTDIR}"
    fi
}

##
## Here is a list of dependencies for the cross-rootfs build under
## dotnet/runtime. These will need to be installed from a pkg
## distribution compatible with the release for the cross-rootfs
## base.txz used in the build
##
## similarly, these are runtime dependencies for the cross-built bundles
##
##
## For selecting a GSS-API provider in the cross rootfs build,
## CROSS_DEP_KRB should be of one of the following values:
##
## - "heimdal", denoting the port security/heimdal
##
## - "mit", denoting the port security/krb5
##
## - an empty string, "" (the default) denoting that the base.txz
##   archive will have installed the GSS-API headers and libraries
##   needed for the build. Alternately under this configuration, a
##   Kerberos 5 distribution may be installed to the cross rootfs, in
##   some way external to this script.
##
## At least one Kerberos 5 installation should be available under
## CROSS_ROOTFS/usr or CROSS_ROOTFS/usr/local or the build may fail
## in a dependency on GSS-API support.
##
## The default here is to use an empty CROSS_DEP_KRB5. This may not be
## compatible with every FreeBSD base.txz distribution, such that may
## not have been built with Kerberos 5 support.
##
CROSS_DEPS=(libunwind icu lttng-ust liburcu libinotify)
case ${CROSS_DEP_KRB5:-} in
    heimdal)
        CROSS_DEPS+=heimdal
        ;;
    mit)
        CROSS_DEPS+=krb5
        ;;
    "")
        ## nop
        ;;
    *)
        fail "Unkonwn CROSS_DEP_KRB5: ${CROSS_DEP_KRB5}"
        ;;
esac


## tags for automated git checkout/switch
if [ -z "${TAG_RUNTIME:-}" ]; then
    fail "TAG_RUNTIME not provided"
elif [ -z "${TAG_ASPNETCORE:-}" ]; then
    fail "TAG_ASPNETCORE not provided"
elif [ -z "${TAG_INSTALLER:-}" ]; then
    fail "TAG_INSTALLER not provided"
fi

if [ -n "${GITHUB_REF:-}" ]; then
    ## provided in the GitHub Workflow environment,
    ## when a reference is avaialble for this repository
    BUILDER_REF="--branch ${GITHUB_REF}"
fi

msg "Beginning build ${BUILD_ID}"

if [ -e "${BUILDER_ROOT}" ]; then
    ## local build - do not update the source tree under BUILDER_ROOT
    msg "builder root already available, skipping clone: ${BUILDER_ROOT}"
else
    ## clone the repository defining the active GitHub Workflow
    ## (GitHub/Docker environment)
    git clone --depth 1 ${BUILDER_REF} \
        ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}.git ${BUILDER_ROOT}
fi

if [ -n "${GITHUB_SHA:-}" ]; then
    ## If GITHUB_SHA is defined, using the value as a head changeset for
    ## this repository
    ## (GitHub/Docker environment)
    git checkout ${GITHUB_SHA} ${BUILDER_ROOT}
    cd ${BUILDER_ROOT}
fi

## clone/reset and patch each working tree
if building_runtime; then
    init_tree ${RUNTIME_ROOT} ${TAG_RUNTIME}
fi
if building_aspnetcore; then
    init_tree ${ASPNETCORE_ROOT} ${TAG_ASPNETCORE}
fi
if building_installer; then
    init_tree ${INSTALLER_ROOT} ${TAG_INSTALLER}
fi

mkdir -p ${TMPDIR} ${ROOTFS_DIR} ${CACHEDIR}/nupkg

## fetch and install each dotnet SDK bundle
if building_runtime; then
    fetch_dotnet "${RUNTIME_ROOT}"
fi
if building_aspnetcore; then
    fetch_dotnet "${ASPNETCORE_ROOT}"
fi
if building_installer; then
    fetch_dotnet "${INSTALLER_ROOT}"
fi

## fetch and install the cross rootfs
if building_runtime && ! [ -e "${ROOTFS_DIR}/bin/freebsd-version" ]; then
    ## FIXME no option for 'clean' here other than to remove ROOTFS_DIR
    ## external to this script
    ##
    ## FIXME needs build-deps installed
    msg "Fetching cross base system (${CROSS_RELEASE}) from ${CROSS_ORIGIN}"
    wget -O "${CACHEDIR}/base.txz" -c ${WGET_ARGS} \
         "${CROSS_ORIGIN}/amd64/${CROSS_RELEASE}/base.txz"
    msg "Extracing cross base system (${CROSS_RELEASE}) to ${ROOTFS_DIR}"
    bsdtar --no-fflags -C ${ROOTFS_DIR} -Jx -f ${CACHEDIR}/base.txz
fi

BUILDER_ENV=(ROOTFS_DIR="${ROOTFS_DIR}" TMPDIR="${TMPDIR}")
BUILDER_ENV+=(NUGET_PACKAGES="${CACHEDIR}/nupkg")

if [ -n "${ALL_PROXY}" ]; then
    ## set proxy environment for fetch
    BUILDER_ENV+=(ALL_PROXY="${ALL_PROXY}")
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

##
## ** dotnet/runtime **
##

## build the runtime framework
if building_runtime; then
    build_tree ${RUNTIME_ROOT} \
               -ninja -cross -os freebsd
fi

##
## ** dotnet/aspnetcore **
##

if building_aspnetcore; then
    ## add the dotnet runtime artifacts dir to aspnetcore nupkg sources
    nuget_source_add \
        runtime \
        ${RUNTIME_ROOT}/artifacts/packages/Release/Shipping \
        ${ASPNETCORE_ROOT}

    ## add resources from the dotnet/runtime build
    sync_runtime_build dotnet \
        ${RUNTIME_ROOT}/artifacts/packages/Release/Shipping \
        ${ASPNETCORE_ROOT}/artifacts/obj/Microsoft.AspNetCore.App.Runtime

    ## --restore and --no-test options should serve to work around
    ## some possible buld failures.
    ##
    ## The added --build options may be redundant to the build
    ## configuration
    build_tree ${ASPNETCORE_ROOT} --restore --no-test \
               --build-native --build-managed \
               --build-nodejs --build-installers \
               --os-name freebsd --pack /p:CrossgenOutput=false
fi


##
## ** dotnet/installer **
##

if building_installer; then
    ## trim internal feeds from installer's nuget sources,
    ## add nupkg output dirs from runtime, aspnetcore builds
    nuget_source_rem msbuild ${INSTALLER_ROOT}
    nuget_source_rem nuget-build ${INSTALLER_ROOT}
    nuget_source_add \
        runtime \
        ${RUNTIME_ROOT}/artifacts/packages/Release/Shipping \
        ${INSTALLER_ROOT}
    nuget_source_add \
        aspnetcore \
        ${ASPNETCORE_ROOT}/artifacts/packages/Release/Shipping \
        ${INSTALLER_ROOT}
    ## add resources from runtime, aspnetcore builds
    sync_runtime_build runtime \
        ${RUNTIME_ROOT}/artifacts/packages/Release/Shipping \
        ${INSTALLER_ROOT}/artifacts/obj/redist/Release/downloads
    sync_runtime_build aspnetcore \
        ${ASPNETCORE_ROOT}/artifacts/installers/Release \
        ${INSTALLER_ROOT}/artifacts/obj/redist/Release/downloads

    ## build the installer
    build_tree "${INSTALLER_ROOT}" \
               -pack --runtime-id freebsd-x64 \
               /p:OSName=freebsd /p:CrossgenOutput=false \
               /p:IncludeAspNetCoreRuntime=True /p:DISABLE_CROSSGEN=True
fi

## Output dirs for external sync (builder workflow environment)
## ${RUNTIME_ROOT}/artifacts/packages/Release/Shipping
## ${ASPNETCORE_ROOT}/artifacts/installers/Release
## ${ASPNETCORE_ROOT}/artifacts/packages/Release/Shipping
## ${INSTALLER_ROOT}/artifacts/packages/Release/Shipping
