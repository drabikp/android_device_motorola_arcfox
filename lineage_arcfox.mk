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
