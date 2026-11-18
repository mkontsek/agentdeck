#!/bin/bash
# Package AgentDeck as a disk image in build/dist.
#
#   make dmg              AgentDeck-<version>.dmg: universal Release app, Developer ID signed with the hardened
#                         runtime, notarized, stapled and verified. This is the only image that may be published.
#   make dmg UNSIGNED=1   AgentDeck-<version>-unsigned.dmg: the same layout with the ad-hoc build signature,
#                         for local testing. Gatekeeper rejects it; never publish it.
#
# Environment:
#   DEVELOPER_ID     name or SHA-1 of a "Developer ID Application" identity; detected when exactly one exists
#   NOTARY_PROFILE   notarytool keychain profile (default: agentdeck-notary)
#
# The script uploads only to Apple's notary service. It never creates a release or uploads the image anywhere.
set -euo pipefail

APP=AgentDeck
BUNDLE_ID=io.kontsek.agentdeck
DERIVED=${DERIVED:-build}
DIST=$DERIVED/dist
PRODUCT=$DERIVED/Build/Products/Release/$APP.app
NOTARY_PROFILE=${NOTARY_PROFILE:-agentdeck-notary}
UNSIGNED=${UNSIGNED:-0}
IDENTITY=
STAGE=
MOUNT=

fail() {
    echo "make-dmg: $*" >&2
    exit 1
}

step() { echo "==> $*"; }

cleanup() {
    if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet -force || true; fi
    if [ -n "$STAGE" ]; then rm -rf "$STAGE"; fi
    MOUNT=
    STAGE=
}

# Sets IDENTITY to the SHA-1 of the one "Developer ID Application" identity to sign with.
resolve_identity() {
    local identities matches count
    identities=$(security find-identity -v -p codesigning |
        sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "\(Developer ID Application: .*\)"$/\1 \2/p')
    if [ -n "${DEVELOPER_ID:-}" ]; then
        matches=$(printf '%s\n' "$identities" |
            awk -v id="$DEVELOPER_ID" '$1 == id || substr($0, 42) == id { print $1 }')
        [ -n "$matches" ] ||
            fail "DEVELOPER_ID does not name a valid \"Developer ID Application\" identity in the keychain."
    else
        matches=$(printf '%s\n' "$identities" | awk 'NF { print $1 }')
    fi
    count=$(printf '%s\n' "$matches" | awk 'NF' | wc -l | tr -d ' ')
    case $count in
    0)
        fail "no \"Developer ID Application\" signing identity in the keychain. Create one under" \
            "developer.apple.com > Certificates, or run 'make dmg UNSIGNED=1' for a local test image."
        ;;
    1) IDENTITY=$matches ;;
    *)
        printf '%s\n' "$identities" >&2
        fail "$count \"Developer ID Application\" identities match; set DEVELOPER_ID to one SHA-1 or name above."
        ;;
    esac
}

require_notary_profile() {
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
        fail "notarytool cannot use the keychain profile \"$NOTARY_PROFILE\". Create it with" \
            "'xcrun notarytool store-credentials $NOTARY_PROFILE', or set NOTARY_PROFILE."
}

is_macho() { [[ $(file -b "$1") == *Mach-O* ]]; }

contains_code() {
    local file
    while IFS= read -r -d '' file; do
        if is_macho "$file"; then return 0; fi
    done < <(find "$1" -type f -print0)
    return 1
}

# Prints nested code, deepest first, NUL separated: loose Mach-O files other than the app's own executable, and
# bundles that contain code. Inner code has to be sealed before the bundle around it is signed.
nested_code() {
    local app=$1 item
    find "$app/Contents" -depth -mindepth 1 -print0 | while IFS= read -r -d '' item; do
        if [ -L "$item" ]; then
            continue
        elif [ -f "$item" ]; then
            if [ "$item" != "$app/Contents/MacOS/$APP" ] && is_macho "$item"; then printf '%s\0' "$item"; fi
        elif [ -d "$item" ]; then
            case $item in
            *.framework | *.app | *.xpc | *.appex | *.bundle | *.plugin)
                if contains_code "$item"; then printf '%s\0' "$item"; fi
                ;;
            esac
        fi
    done
}

sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }

# Submits one file and fails unless Apple accepts it.
notarize() {
    local file=$1 result id status
    step "Notarizing $(basename "$file") (waits for Apple)"
    result=$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json) ||
        fail "notarytool could not submit $(basename "$file")."
    id=$(printf '%s' "$result" | plutil -extract id raw -o - - 2>/dev/null || true)
    status=$(printf '%s' "$result" | plutil -extract status raw -o - - 2>/dev/null || true)
    if [ "$status" != Accepted ]; then
        if [ -n "$id" ]; then xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true; fi
        fail "notarization of $(basename "$file") ended as \"${status:-unknown}\" (submission ${id:-unknown})."
    fi
    echo "Accepted: submission $id"
}

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }

require_universal() {
    local archs
    archs=" $(lipo -archs "$1/Contents/MacOS/$APP") "
    [[ $archs == *" arm64 "* && $archs == *" x86_64 "* ]] || fail "$1 is not universal:$archs"
}

main() {
    local version root staged image mounted nested item entitlements assessment output

    case $UNSIGNED in
    0 | 1) ;;
    *) fail "UNSIGNED must be 0 or 1." ;;
    esac

    # Check the credentials before the build, so a missing one costs seconds.
    if [ "$UNSIGNED" = 0 ]; then
        resolve_identity
        require_notary_profile
    fi

    step "Building the universal Release app"
    make build CONFIG=Release DERIVED="$DERIVED"
    [ -d "$PRODUCT" ] || fail "the build left no app at $PRODUCT."
    [ "$(plist_value "$PRODUCT" CFBundleIdentifier)" = "$BUNDLE_ID" ] || fail "$PRODUCT is not $BUNDLE_ID."
    version=$(plist_value "$PRODUCT" CFBundleShortVersionString)
    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "unexpected version \"$version\"."
    require_universal "$PRODUCT"

    mkdir -p "$DIST"
    if [ "$UNSIGNED" = 0 ]; then
        output=$DIST/$APP-$version.dmg
    else
        output=$DIST/$APP-$version-unsigned.dmg
    fi
    # A run that fails from here on must not leave an older image under this name.
    rm -f "$output"

    trap cleanup EXIT
    STAGE=$(mktemp -d "${TMPDIR:-/tmp}/agentdeck-dmg.XXXXXX")
    root=$STAGE/root
    staged=$root/$APP.app
    image=$STAGE/$APP.dmg
    mkdir "$root"
    ditto "$PRODUCT" "$staged"
    ln -s /Applications "$root/Applications"

    if [ "$UNSIGNED" = 0 ]; then
        step "Signing nested code, then the app"
        nested=0
        while IFS= read -r -d '' item; do
            sign "$item"
            nested=$((nested + 1))
        done < <(nested_code "$staged")
        echo "Nested code items signed: $nested"
        # Re-signing drops whatever entitlements the build carried; the app ships with none.
        sign "$staged"
        codesign --verify --deep --strict --verbose=2 "$staged"

        # The app is notarized and stapled first, so the copy inside the image passes Gatekeeper offline too.
        ditto -c -k --keepParent "$staged" "$STAGE/$APP.zip"
        notarize "$STAGE/$APP.zip"
        xcrun stapler staple "$staged"
    fi

    step "Creating the disk image"
    hdiutil create -volname "$APP" -srcfolder "$root" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov -quiet "$image"

    if [ "$UNSIGNED" = 0 ]; then
        step "Signing, notarizing and stapling the disk image"
        codesign --force --timestamp --sign "$IDENTITY" "$image"
        notarize "$image"
        xcrun stapler staple "$image"
    fi

    step "Verifying the disk image"
    hdiutil verify -quiet "$image"
    mkdir "$STAGE/volume"
    hdiutil attach "$image" -readonly -nobrowse -noautoopen -mountpoint "$STAGE/volume" -quiet
    MOUNT=$STAGE/volume
    mounted=$MOUNT/$APP.app
    [ "$(readlink "$MOUNT/Applications")" = /Applications ] || fail "the image has no /Applications link."
    [ "$(plist_value "$mounted" CFBundleShortVersionString)" = "$version" ] ||
        fail "the image holds another version."
    require_universal "$mounted"
    codesign --verify --deep --strict --verbose=2 "$mounted"
    [[ $(codesign --display --verbose=4 "$mounted" 2>&1) =~ flags=0x[0-9a-f]+\([a-z,-]*runtime[a-z,-]*\) ]] ||
        fail "the app is not signed with the hardened runtime."
    entitlements=$(codesign --display --entitlements - --xml "$mounted" 2>/dev/null || true)
    [ -z "$entitlements" ] || fail "the app must ship without entitlements, but carries: $entitlements"
    if [ "$UNSIGNED" = 0 ]; then
        assessment=$(spctl -a -vv "$mounted" 2>&1) || fail "Gatekeeper rejects the app: $assessment"
        echo "$assessment"
        [[ $assessment == *"source=Notarized Developer ID"* ]] || fail "the app is not notarized."
        assessment=$(spctl -a -t open --context context:primary-signature -vv "$image" 2>&1) ||
            fail "Gatekeeper rejects the disk image: $assessment"
        echo "$assessment"
        [[ $assessment == *"source=Notarized Developer ID"* ]] || fail "the disk image is not notarized."
        xcrun stapler validate "$mounted"
        xcrun stapler validate "$image"
    fi
    hdiutil detach "$MOUNT" -quiet
    MOUNT=

    mv -f "$image" "$output"
    cleanup

    step "Removing duplicate app bundles"
    make cleanup-installs DERIVED="$DERIVED" ||
        echo "make-dmg: cleanup-installs left the build products in place (see its message above)." \
            "Run 'make install' for this version, or 'make cleanup-installs' once it is installed." >&2

    echo
    if [ "$UNSIGNED" = 0 ]; then
        echo "Notarized disk image: $output"
    else
        echo "UNSIGNED TEST IMAGE, DO NOT PUBLISH: $output"
    fi
    echo "SHA-256: $(shasum -a 256 "$output" | cut -d' ' -f1)"
}

# The packaging tests source this file for its functions; the build runs only when it is executed.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    cd "$(dirname "$0")/.."
    main
fi
