#!/bin/sh
set -eu
# TEMP_DIR is writable recursively in Xcode's script sandbox; declared output
# directories under DERIVED_FILE_DIR are allowed only as literal paths.
reader_build_dir="${TEMP_DIR}/ClipboardReader"
reader_destination="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/ArsWidgetClipboardReader"
mkdir -p "$reader_build_dir" "$(dirname "$reader_destination")"
for reader_arch in $ARCHS; do
    xcrun swiftc -O -sdk "$SDKROOT" -target "${reader_arch}-apple-macos${MACOSX_DEPLOYMENT_TARGET}" \
        -module-cache-path "$reader_build_dir/ModuleCache" \
        "$SRCROOT/ArsWidget/managers/ClipboardTextReader.swift" \
        "$SRCROOT/tools/clipboard-reader/main.swift" \
        -o "$reader_build_dir/reader-$reader_arch"
done
# Paths may contain spaces: reconstruct the argument list from ARCHS.
set --
for reader_arch in $ARCHS; do set -- "$@" "$reader_build_dir/reader-$reader_arch"; done
# lipo and codesign create temporary siblings. Keep all of those inside
# TEMP_DIR, then copy only the final file to the declared app output.
reader_output="$reader_build_dir/ArsWidgetClipboardReader"
xcrun lipo -create "$@" -output "$reader_output"
if [ "${CODE_SIGNING_ALLOWED:-NO}" != NO ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" \
        --entitlements "$SRCROOT/tools/clipboard-reader/ClipboardReader.entitlements" "$reader_output"
fi
cp "$reader_output" "$reader_destination"
