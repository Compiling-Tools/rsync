#!/bin/sh
# Print an SPDX 2.3 SBOM for $1: the rsync binary, or its relink archive when
# $2 is libs. Called by recipe.sh
# at the end of the build, as it reads from build/: the components are the
# pinned sources from sources.txt, the libraries bundled inside rsync's
# tarball, and the parts of the Alpine toolchain that get linked in. recipe.sh
# checks the linker map to make sure exactly these libraries are in the binary.
set -eu
artifact=$(realpath "$1")
scope=${2:-binary}
case $scope in binary | libs) ;; *) echo "error: unknown SBOM scope: $scope" >&2; exit 1 ;; esac
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
rsync_url=$(awk '$1 == "rsync" { print $4 }' sources.txt)
rsync_sha256=$(awk '$1 == "rsync" { print $3 }' sources.txt)
arch=$(apk --print-arch)
artifact_sha256=$(sha256sum "$artifact")
artifact_sha256=${artifact_sha256%% *}
created=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)
zlib_version=$(sed -n 's/^#define ZLIB_VERSION "\(.*\)"/\1/p' build/rsync/zlib/zlib.h)
[ -n "$zlib_version" ] || { echo "error: no version for zlib" >&2; exit 1; }
zstd_xxhash_version=$(awk '/^#define XXH_VERSION_(MAJOR|MINOR|RELEASE) / { print $3 }' build/zstd/lib/common/xxhash.h | paste -sd.)
[ -n "$zstd_xxhash_version" ] || { echo "error: no version for zstd xxHash" >&2; exit 1; }
# musl's memcpy for 32-bit ARM comes from Android under BSD-2-Clause.
case $arch in
    armhf | armv7) musl_license="MIT AND BSD-2-Clause" ;;
    *) musl_license=MIT ;;
esac

# The components go to a file rather than straight into jq: in a pipeline the
# exit status of everything but jq is lost, so a failure would go unnoticed.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
components=$tmp/components
files=$tmp/files
: > "$files"
{
    grep -v '^#' sources.txt | while read -r name version sha256 url cpe license; do
        [ -n "$name" ] || continue
        if [ "$cpe" = - ]; then cpe=; else cpe="cpe:2.3:a:$cpe:$version:*:*:*:*:*:*:*"; fi
        package "$name" "$version" "$url" "$sha256" "$license" "$cpe" ""
    done
    package zstd-xxhash "$zstd_xxhash_version" "$(awk '$1 == "zstd" { print $4 }' sources.txt)" "" BSD-3-Clause "" \
        "Adapted xxHash copy bundled in zstd's lib/common/xxhash.h"
    package popt "" "$rsync_url" "" X11 "" "Copy bundled in the rsync source tarball"
    zlib_fork_version=$zlib_version-rsync-$rsync_version
    package zlib "$zlib_fork_version" "$rsync_url" "" Zlib "pkg:generic/rsync/zlib@$zlib_fork_version" \
        "rsync-maintained fork of upstream zlib $zlib_version with backported fixes; enclosed by rsync $rsync_version source tarball SHA-256 $rsync_sha256. CVE reviews, if any, are per source tarball in zlib.vex.json."
    if [ "$scope" = libs ]; then
        package zstd-divsufsort "" "$(awk '$1 == "zstd" { print $4 }' sources.txt)" "" MIT "" \
            "lib/dictBuilder/divsufsort.c is included in the complete libzstd.a archive, but is not linked into the rsync executable"
    else
        musl_version=$(apk_version musl-dev)
        gcc_version=$(apk_version gcc)
        alpine=alpine-$(cat /etc/alpine-release)
        # Alpine's packages, so that scanners know about Alpine's security fixes.
        package musl "$musl_version" https://musl.libc.org/ "" "$musl_license" \
            "pkg:apk/alpine/musl@$musl_version?arch=$arch&distro=$alpine" \
            "libc.a, and libssp_nonshared.a where the architecture needs it, from the Alpine toolchain"
        package libgcc "$gcc_version" https://gcc.gnu.org/ "" \
            "GPL-3.0-or-later WITH GCC-exception-3.1" \
            "pkg:apk/alpine/gcc@$gcc_version?arch=$arch&distro=$alpine" \
            "GCC runtime from the Alpine toolchain: crtbegin/crtend, and libgcc.a where the architecture needs it"
    fi
} > "$components"

expected=$(grep -v '^#' sources.txt | awk 'NF { print $1 }'; printf '%s\n' zstd-xxhash popt zlib
    if [ "$scope" = libs ]; then echo zstd-divsufsort; else printf '%s\n' musl libgcc; fi)
if [ "$(jq -r .name "$components")" != "$expected" ]; then
    echo "error: the SBOM is missing components" >&2
    exit 1
fi

verification=
if [ "$scope" = libs ]; then
    mkdir "$tmp/members"
    tar -xzf "$artifact" -C "$tmp/members"
    find "$tmp/members" -type f | LC_ALL=C sort | while read -r member; do
        name=${member#"$tmp/members/"}
        id=$(printf '%s' "$name" | tr '/_' '--')
        sha256=$(sha256sum "$member"); sha256=${sha256%% *}
        sha1=$(sha1sum "$member"); sha1=${sha1%% *}
        jq -n --arg name "$name" --arg id "$id" --arg sha256 "$sha256" --arg sha1 "$sha1" '{
            SPDXID: "SPDXRef-File-\($id)", fileName: "./\($name)",
            checksums: [{algorithm: "SHA256", checksumValue: $sha256}, {algorithm: "SHA1", checksumValue: $sha1}],
            licenseConcluded: "NOASSERTION", licenseInfoInFiles: ["NOASSERTION"], copyrightText: "NOASSERTION"
        }'
    done > "$files"
    verification=$(jq -r '.checksums[] | select(.algorithm == "SHA1") | .checksumValue' "$files" | LC_ALL=C sort | tr -d '\n' | sha1sum)
    verification=${verification%% *}
fi

jq -s --arg version "$rsync_version" --arg arch "$arch" \
    --arg sha256 "$artifact_sha256" --arg created "$created" --arg epoch "$SOURCE_DATE_EPOCH" \
    --arg scope "$scope" --arg filename "$(basename "$artifact")" --arg verification "$verification" \
    --slurpfile files "$files" '
    . as $components
    | (if $scope == "libs" then "rsync-libs" else "rsync-static" end) as $name
    | {
        SPDXID: "SPDXRef-Package-\($name)",
        name: $name,
        versionInfo: $version,
        packageFileName: $filename,
        downloadLocation: "NOASSERTION",
        checksums: [{algorithm: "SHA256", checksumValue: $sha256}],
        filesAnalyzed: ($scope == "libs"),
        primaryPackagePurpose: (if $scope == "libs" then "ARCHIVE" else "APPLICATION" end),
        licenseConcluded: ([$components[].licenseConcluded | split(" AND ")[]] | unique | join(" AND ")),
        licenseDeclared: "NOASSERTION",
        copyrightText: "NOASSERTION",
        comment: (if $scope == "libs" then "Relinking archive for \($arch); complete static libraries, rsync application objects, relink script and notices. musl and GCC runtime are supplied by the relinking toolchain."
            else "Statically linked rsync executable for \($arch)" end)
    } + (if $scope == "libs" then {packageVerificationCode: {packageVerificationCodeValue: $verification}, licenseInfoFromFiles: ["NOASSERTION"]} else {} end) as $artifact
    | {
        spdxVersion: "SPDX-2.3",
        dataLicense: "CC0-1.0",
        SPDXID: "SPDXRef-DOCUMENT",
        name: "\($name)-\($version)-\($arch)",
        documentNamespace: "https://github.com/Compiling-Tools/rsync/spdx/\($version)-\($arch)-\($sha256)-\($epoch)",
        creationInfo: {created: $created, creators: ["Tool: static-rsync sbom.sh"]},
        packages: ([$artifact] + $components),
        relationships: (
            [{spdxElementId: "SPDXRef-DOCUMENT", relationshipType: "DESCRIBES", relatedSpdxElement: $artifact.SPDXID}]
            + [$components[] | {
                spdxElementId: (if .name == "zstd-xxhash" or .name == "zstd-divsufsort" then "SPDXRef-Package-zstd"
                    elif .name == "popt" or .name == "zlib" then "SPDXRef-Package-rsync" else $artifact.SPDXID end),
                relationshipType: (if .name == "zstd-xxhash" or .name == "zstd-divsufsort" or .name == "popt" or .name == "zlib" then "CONTAINS"
                    elif .name == "rsync" or $scope == "libs" then "GENERATED_FROM" else "STATIC_LINK" end),
                relatedSpdxElement: .SPDXID
            }]
            + [$components[] | select($scope == "binary" and (.name == "popt" or .name == "zlib"))
                | {spdxElementId: $artifact.SPDXID, relationshipType: "STATIC_LINK", relatedSpdxElement: .SPDXID}]
            + [$files[] | {spdxElementId: $artifact.SPDXID, relationshipType: "CONTAINS", relatedSpdxElement: .SPDXID}]
            + [$files[] | . as $file | ({"./libacl.a": "acl", "./libcrypto.a": "openssl", "./libzstd.a": "zstd", "./liblz4.a": "lz4", "./libxxhash.a": "xxhash", "./rsync.o": "rsync"}[.fileName]) as $source
                | select($source != null) | {spdxElementId: $file.SPDXID, relationshipType: "GENERATED_FROM", relatedSpdxElement: "SPDXRef-Package-\($source)"}]
        )
    } + (if $scope == "libs" then {files: $files} else {} end)' "$components"
