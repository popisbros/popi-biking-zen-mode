#!/bin/bash

# Crashlytics dSYM Upload Script
# This script uploads dSYM files to Firebase Crashlytics after each build

# Don't fail the build if this script encounters errors
# set -e

# Only run for Release and Profile builds (not Debug)
if [ "${CONFIGURATION}" == "Debug" ]; then
    echo "Skipping dSYM upload for Debug configuration"
    exit 0
fi

# Check if Firebase Crashlytics script exists
CRASHLYTICS_SCRIPT="${PODS_ROOT}/FirebaseCrashlytics/upload-symbols"

if [ ! -f "$CRASHLYTICS_SCRIPT" ]; then
    echo "Warning: Firebase Crashlytics upload-symbols script not found at $CRASHLYTICS_SCRIPT"
    echo "Make sure firebase_crashlytics plugin is installed and pods are up to date"
    exit 0
fi

# Check if dSYM file exists
if [ ! -d "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}" ]; then
    echo "Warning: dSYM file not found at ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}"
    echo "Skipping dSYM upload"
    exit 0
fi

# Upload dSYMs (don't fail build if upload fails)
echo "Uploading dSYM files to Crashlytics..."
"${CRASHLYTICS_SCRIPT}" \
    -gsp "${PROJECT_DIR}/Runner/GoogleService-Info.plist" \
    -p ios \
    "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}" || {
    echo "Warning: dSYM upload failed, but continuing build"
    exit 0
}

echo "dSYM upload complete"
