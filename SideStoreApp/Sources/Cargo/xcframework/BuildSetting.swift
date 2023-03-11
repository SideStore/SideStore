//
//  BuildSettings.swift
//  Cargo
//
//  Created by Joseph Mattiello on 02/28/23.
//  Copyright © 2023 Joseph Mattiello. All rights reserved.
//


//set -eu;
//
//BUILT_SRC="./em_proxy/$LIB_FILE_NAME.a"
//ln -f -- "$BUILT_SRC" "$TARGET_BUILD_DIR/$EXECUTABLE_PATH" || cp "$BUILT_SRC" "$TARGET_BUILD_DIR/$EXECUTABLE_PATH"
//echo "$BUILT_SRC -> $TARGET_BUILD_DIR/$EXECUTABLE_PATH"

//# generated with cargo-xcode 1.5.0
//# modified to use prebuilt binaries
//
//set -eu;
//
//BUILT_SRC="./minimuxer/$LIB_FILE_NAME.a"
//ln -f -- "$BUILT_SRC" "$TARGET_BUILD_DIR/$EXECUTABLE_PATH" || cp "$BUILT_SRC" "$TARGET_BUILD_DIR/$EXECUTABLE_PATH"
//echo "$BUILT_SRC -> $TARGET_BUILD_DIR/$EXECUTABLE_PATH"
//
//# xcode generates dep file, but for its own path, so append our rename to it
//										#DEP_FILE_SRC="minimuxer/target/${CARGO_XCODE_TARGET_TRIPLE}/release/${CARGO_XCODE_CARGO_DEP_FILE_NAME}"
//										#if [ -f "$DEP_FILE_SRC" ]; then
//#    DEP_FILE_DST="${DERIVED_FILE_DIR}/${CARGO_XCODE_TARGET_ARCH}-${EXECUTABLE_NAME}.d"
//#    cp -f "$DEP_FILE_SRC" "$DEP_FILE_DST"
//#    echo >> "$DEP_FILE_DST" "$SCRIPT_OUTPUT_FILE_0: $BUILT_SRC"
//#fi
//
//# lipo script needs to know all the platform-specific files that have been built
//# archs is in the file name, so that paths don't stay around after archs change
//# must match input for LipoScript
//						#FILE_LIST="${DERIVED_FILE_DIR}/${ARCHS}-${EXECUTABLE_NAME}.xcfilelist"
//						#touch "$FILE_LIST"
//						#if ! egrep -q "$SCRIPT_OUTPUT_FILE_0" "$FILE_LIST" ; then
//#    echo >> "$FILE_LIST" "$SCRIPT_OUTPUT_FILE_0"
//#fi


import ArgumentParser

/// A representation of a build setting in an Xcode project, e.g.
/// `IPHONEOS_DEPLOYMENT_TARGET=13.0`
struct BuildSetting: ExpressibleByArgument {
    /// The name of the build setting, e.g. `IPHONEOS_DEPLOYMENT_TARGET`
    let name: String
    /// The value of the build setting
    let value: String

    init?(argument: String) {
        let components = argument.components(separatedBy: "=")
        guard components.count == 2 else { return nil }
        name = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        value = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
