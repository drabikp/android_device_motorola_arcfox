#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
# arcfox is 64-bit ONLY: stock system/lib has zero 32-bit .so files and
# vendor/lib has 3 stubs vs 1221 in vendor/lib64. Using core_64_bit.mk
# builds a 32-bit variant that consumes arm64 kernel UAPI headers and
# fails with "unknown type name '__uint128_t'" in asm/sigcontext.h.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# BRING-UP ONLY -- REMOVE BEFORE ANY GENERAL RELEASE.
#
# WITH_ADB_INSECURE is LineageOS's own supported knob
# (vendor/lineage/config/common.mk:33-43). On a userdebug build it does two things:
#   ro.adb.secure=0   -- adb needs no key authorization
#   skips PRODUCT_NOT_DEBUGGABLE_IN_USERDEBUG, so ro.debuggable=1 -> `adb root`
#
# Both are wanted while porting. adb kept lapsing to "unauthorized" after every
# flash, and an unauthorized device refuses `reboot` as well as `shell`, so each
# lapse cost a manual power-cycle -- the exact brake the USB fix was meant to
# remove. The underlying cause is a real defect that this only masks:
#   W AdbDebuggingManager: adbd_auth domain socket unavailable
# so system_server cannot run the authorization handshake at all. Fix that and
# this can go.
#
# ro.debuggable=1 additionally buys `adb root`, which makes sepolicy work, /data
# and tombstone inspection, and property experiments possible without a reflash.
#
# It MUST be set before the inherit below: common.mk tests it with ifdef at parse
# time, so setting it afterwards has no effect.
#
# Security note: this build has no adb key checking and allows adb root. That is
# acceptable only because the device is a development target and is not being
# daily-driven (owner's explicit decision, 2026-08-09). Delete this line the
# moment that changes.
WITH_ADB_INSECURE := true

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit from arcfox device
$(call inherit-product, device/motorola/arcfox/device.mk)

PRODUCT_NAME := lineage_arcfox
PRODUCT_DEVICE := arcfox
PRODUCT_MANUFACTURER := motorola
PRODUCT_BRAND := motorola
PRODUCT_MODEL := motorola razr 50 ultra

PRODUCT_GMS_CLIENTID_BASE := android-motorola

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="arcfox_g-user 16 W1UXS36H.72-45-10-7 33779-0863b release-keys" \
    BuildFingerprint=motorola/arcfox_g/arcfox:16/W1UXS36H.72-45-10-7/33779-0863b:user/release-keys \
    DeviceName=arcfox \
    DeviceProduct=arcfox_g
