#!/bin/sh
# Print an SPDX 2.3 SBOM for the rsync binary given as $1. Called by recipe.sh
# at the end of the build, as it reads from build/: the components are the
# pinned sources from sources.txt, the libraries bundled inside rsync's
# tarball, and the parts of the Alpine toolchain that get linked in. recipe.sh
# checks the linker map to make sure exactly these libraries are in the binary.
set -eu
binary=$(realpath "$1")
cd "$(dirname "$0")"

# package ID VERSION URL SHA256 LICENSE REF COMMENT: print one SPDX package.
# REF is a CPE or a purl, which vulnerability scanners match on. Empty fields
# are left out.
package() {
    jq -n --arg id "$1" --arg version "$2" --arg url "$3" --arg sha256 "$4" \
        --arg license "$5" --arg ref "$6" --arg comment "$7" '{
            SPDXID: "SPDXRef-Package-\($id)",
            name: $id,
            versionInfo: $version,
            downloadLocation: $url,
            checksums: (if $sha256 == "" then "" else [{algorithm: "SHA256", checksumValue: $sha256}] end),
            filesAnalyzed: false,
            licenseConcluded: $license,
            licenseDeclared: "NOASSERTION",
            copyrightText: "NOASSERTION",
            externalRefs: (if $ref == "" then ""
                elif ($ref | startswith("pkg:")) then
                    [{referenceCategory: "PACKAGE-MANAGER", referenceType: "purl", referenceLocator: $ref}]
                else
                    [{referenceCategory: "SECURITY", referenceType: "cpe23Type", referenceLocator: $ref}]
                end),
            comment: $comment
        } | with_entries(select(.value != ""))'
}

# apk_version PACKAGE: print the installed version of an Alpine package.
apk_version() {
    version=$(apk query --installed --fields version "$1" | sed -n 's/^Version: //p')
    [ -n "$version" ] || { echo "error: no version for $1" >&2; exit 1; }
    echo "$version"
}

rsync_version=$(awk '$1 == "rsync" { print $2 }' sources.txt)
arch=$(apk --print-arch)
binary_sha256=$(sha256sum "$binary")
binary_sha256=${binary_sha256%% *}
created=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)
musl_version=$(apk_version musl-dev)
gcc_version=$(apk_version gcc)
alpine=alpine-$(cat /etc/alpine-release)
zlib_version=$(sed -n 's/^#define ZLIB_VERSION "\(.*\)"/\1/p' build/rsync/zlib/zlib.h)
[ -n "$zlib_version" ] || { echo "error: no version for zlib" >&2; exit 1; }
# musl's memcpy for 32-bit ARM comes from Android under BSD-2-Clause.
case $arch in
    armhf | armv7) musl_license="MIT AND BSD-2-Clause" ;;
    *) musl_license=MIT ;;
esac

# The components go to a file rather than straight into jq: in a pipeline the
# exit status of everything but jq is lost, so a failure would go unnoticed.
components=$(mktemp)
trap 'rm -f "$components"' EXIT
{
    grep -v '^#' sources.txt | while read -r name version sha256 url cpe license; do
        [ -n "$name" ] || continue
        if [ "$cpe" = - ]; then cpe=; else cpe="cpe:2.3:a:$cpe:$version:*:*:*:*:*:*:*"; fi
        package "$name" "$version" "$url" "$sha256" "$license" "$cpe" ""
    done
    package popt "" NOASSERTION "" X11 "" "Copy bundled in the rsync source tarball"
    # Not zlib's CPE: rsync patches its copy, so the CVEs of upstream zlib
    # 1.2.8 do not apply; fixes to it are rsync releases.
    package zlib "$zlib_version" NOASSERTION "" Zlib "pkg:generic/zlib@$zlib_version" \
        "Modified copy bundled in the rsync source tarball"
    # Alpine's packages, so that scanners know about Alpine's security fixes.
    package musl "$musl_version" https://musl.libc.org/ "" "$musl_license" \
        "pkg:apk/alpine/musl@$musl_version?arch=$arch&distro=$alpine" \
        "libc.a, and libssp_nonshared.a where the architecture needs it, from the Alpine toolchain"
    package libgcc "$gcc_version" https://gcc.gnu.org/ "" \
        "GPL-3.0-or-later WITH GCC-exception-3.1" \
        "pkg:apk/alpine/gcc@$gcc_version?arch=$arch&distro=$alpine" \
        "GCC runtime from the Alpine toolchain: crtbegin/crtend, and libgcc.a where the architecture needs it"
} > "$components"

expected=$(grep -v '^#' sources.txt | awk 'NF { print $1 }'; printf '%s\n' popt zlib musl libgcc)
if [ "$(jq -r .name "$components")" != "$expected" ]; then
    echo "error: the SBOM is missing components" >&2
    exit 1
fi

jq -s --arg version "$rsync_version" --arg arch "$arch" \
    --arg sha256 "$binary_sha256" --arg created "$created" --arg epoch "$SOURCE_DATE_EPOCH" '
    . as $components
    | {
        SPDXID: "SPDXRef-Package-rsync-static",
        name: "rsync-static",
        versionInfo: $version,
        packageFileName: "rsync",
        downloadLocation: "NOASSERTION",
        checksums: [{algorithm: "SHA256", checksumValue: $sha256}],
        filesAnalyzed: false,
        primaryPackagePurpose: "APPLICATION",
        licenseConcluded: ([$components[].licenseConcluded | split(" AND ")[]] | unique | join(" AND ")),
        licenseDeclared: "NOASSERTION",
        copyrightText: "NOASSERTION",
        comment: "Statically linked rsync for \($arch)"
    } as $binary
    | {
        spdxVersion: "SPDX-2.3",
        dataLicense: "CC0-1.0",
        SPDXID: "SPDXRef-DOCUMENT",
        name: "rsync-static-\($version)-\($arch)",
        documentNamespace: "https://github.com/Compiling-Tools/rsync/spdx/\($version)-\($arch)-\($sha256)-\($epoch)",
        creationInfo: {created: $created, creators: ["Tool: static-rsync sbom.sh"]},
        packages: ([$binary] + $components),
        relationships: (
            [{spdxElementId: "SPDXRef-DOCUMENT", relationshipType: "DESCRIBES", relatedSpdxElement: $binary.SPDXID}]
            + [$components[] | {
                spdxElementId: $binary.SPDXID,
                relationshipType: (if .name == "rsync" then "GENERATED_FROM" else "STATIC_LINK" end),
                relatedSpdxElement: .SPDXID
            }]
        )
    }' "$components"
