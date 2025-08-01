#!/bin/bash
#
# SPDX-FileCopyrightText: 2016 The CyanogenMod Project
# SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

set -e

export DEVICE=kalama
export VENDOR=qcom

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

# If XML files don't have comments before the XML header, use this flag
# Can still be used with broken XML files by using blob_fixup
export TARGET_DISABLE_XML_FIXING=true

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_COMMON=
ONLY_FIRMWARE=
ONLY_TARGET=
KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-common)
            ONLY_COMMON=true
            ;;
        --only-firmware)
            ONLY_FIRMWARE=true
            ;;
        --only-target)
            ONLY_TARGET=true
            ;;
        -n | --no-cleanup)
            CLEAN_VENDOR=false
            ;;
        -k | --kang)
            KANG="--kang"
            ;;
        -s | --section)
            SECTION="${2}"; shift
            CLEAN_VENDOR=false
            ;;
        *)
            SRC="${1}"
            ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        system_ext/lib64/libwfdnative.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --remove-needed "android.hidl.base@1.0.so" "${2}"
            ;;
        vendor/bin/hw/android.hardware.security.keymint-service-qti)
            [ "$2" = "" ] && return 0
            grep -q "android.hardware.security.rkp-V3-ndk.so" "${2}" || ${PATCHELF} --add-needed "android.hardware.security.rkp-V3-ndk.so" "${2}"
            ;;
        vendor/lib64/libdlbdsservice.so | vendor/lib64/soundfx/libswdap.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --replace-needed "libstagefright_foundation.so" "libstagefright_foundation-v33.so" "${2}"
            ;;
        vendor/etc/seccomp_policy/qwesd@2.0.policy)
            [ "$2" = "" ] && return 0
            echo "pipe2: 1" >> "${2}"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

function blob_fixup_dry() {
    blob_fixup "$1" ""
}

# Initialize the helper for device
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

# Extract files
if [ -z "${ONLY_FIRMWARE}" ]; then
    if [ -f "${MY_DIR}/proprietary-files.txt" ]; then
        extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
    fi
    if [ -f "${MY_DIR}/proprietary-files-carriersettings.txt" ]; then
        extract "${MY_DIR}/proprietary-files-carriersettings.txt" "${SRC}" "${KANG}" --section "${SECTION}"
    fi
fi

# Extract firmware if needed
if [ -z "${SECTION}" ] && [ -f "${MY_DIR}/proprietary-firmware.txt" ]; then
    extract_firmware "${MY_DIR}/proprietary-firmware.txt" "${SRC}"
fi

# Extract carrier settings if any
#extract_carriersettings

# Final makefiles setup
"${MY_DIR}/setup-makefiles.sh"
