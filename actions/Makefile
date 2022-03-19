## actions Makefile (bmake)
##
## based on: build.sh
##
## usage:
##
## # update the Dockerfile for actions, using a FreeBSD host
## make Dockerfile
##
## # same, with bmake from ports or bmake on Linux
## bmake Dockerfile
##
## assumptions:
## - should be usable on FreeBSD or Linux
##
## additional caveats:
##
## - if used on Linux, should be called with 'bmake'
##
## - if used on FreeBSD, will check for installed tools.
##
##   If a tool is not found, this Makefile will emit a
##   warning indicating which port would install the tool
##
## - FreeBSD 12 is supported with docker orchestration
##   for .NET build tools
##   https://github.com/dotnet/dotnet-buildtools-prereqs-docker
##
##   Dockerfile for cross-building for FreeBSD 12
##   https://github.com/dotnet/dotnet-buildtools-prereqs-docker/blob/main/src/ubuntu/18.04/cross/freebsd/12/Dockerfile
##
##   dotnet/versions information used in this scripting
##   https://github.com/dotnet/versions/tree/main/build-info/docker/image-info.dotnet-dotnet-buildtools-prereqs-docker-main.json
##

## GitHub repository for .NET versions information
## default: using https://github.com/dotnet/versions
DOTNET_VERSIONS=	dotnet/versions

## git branch for .NET versions information
## within the DOTNET_VERSIONS repository
DOTNET_VERSIONS_BRANCH=	master

## path for docker build info under .NET versions repository
DOTNET_TOOLS_JSON=	build-info/docker/image-info.dotnet-dotnet-buildtools-prereqs-docker-main.json

## FreeBSD release tag under dotnet dockerfiles for build
## https://github.com/dotnet/dotnet-buildtools-prereqs-docker
FREEBSD_REL=	12

## json evaluation expressions for jq for .NET versions information
## will be quoted when passed to shell
JQ_CROSS_SELECT=	.repos[0].images[] | select(.platforms[0].dockerfile | contains("freebsd/${FREEBSD_REL}"))
JQ_CROSS_TAG=	 	${JQ_CROSS_SELECT} | .platforms[0].simpleTags[0]
JQ_CROSS_IMAGE=		${JQ_CROSS_SELECT} | .platforms[0].digest | split("@")[0]

## tools assumed to be installed in the OS base system
UNAME?=		uname
SED?=		sed
TEE?=		tee
CAT?=		cat

## operating system type
OPSYS!=		${UNAME} -o

## paths independent of OS
BINDIR?=	${PREFIX}/bin

.if "${OPSYS}" == "FreeBSD"
## variables and tests on FreeBSD

PREFIX?=	/usr/local

## port info for build cmds, using FreeBSD ports
BINTOOLS_PORTS=	curl:ftp/curl \
	git:devel/git \
	jq:textproc/jq

## pre-build checks
. for CMD ORGN in ${BINTOOLS_PORTS:S/:/ /}
.  if !eixsts(${BINDIR}/${CMD})
.   warn "Build tool not found: ${BINDIR}/${CMD} (available in port ${ORGN})"
.  endif
. endfor

.elif ## OPSYS != FreeBSD

PREFIX?=	/usr

## set a default FreeBSD release version without testing uname
.endif

## internal variables
CLEANFILES=	${DOTNET_TOOLS_JSON:T} image.tag
REALCLEANFILES=	 Dockerfile

all:	Dockerfile .PHONY

${DOTNET_TOOLS_JSON:T}:
	${BINDIR}/curl -o $@ https://raw.githubusercontent.com/${DOTNET_VERSIONS}/${DOTNET_VERSIONS_BRANCH}/${DOTNET_TOOLS_JSON}

## e.g text
## mcr.microsoft.com/dotnet-buildtools/prereqs:ubuntu-18.04-cross-freebsd-12-20220318070727-f13d79e
image.tag: ${DOTNET_TOOLS_JSON:T}
	${BINDIR}/jq '[ (${JQ_CROSS_IMAGE}), (${JQ_CROSS_TAG}) ] | join(":")' ${DOTNET_TOOLS_JSON:T} | ${SED} 's@"@@g' | ${TEE} $@

## update the Dockerfile
Dockerfile: image.tag dockerfile.in
	TAG=$$(${CAT} image.tag); ${SED} "s@%%FROM%%@$${TAG}@" dockerfile.in | ${TEE} $@

clean: .PHONY
	rm -f ${CLEANFILES}

dockerclean: .PHONY
	rm -f ${REALCLEANFILES}

realclean: clean dockerclean .PHONY

# Local Variables:
# mode: makefile-bsdmake
# End:
