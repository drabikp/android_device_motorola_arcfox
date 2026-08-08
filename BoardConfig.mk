#
# BoardConfig for Motorola razr 50 ultra / razr+ 2024 (arcfox), XT2451-3.
# Measured on W1UXS36H.72-45-10-7 (Android 16), channel reteu.
#

DEVICE_PATH := device/motorola/arcfox

include device/motorola/sm8635-common/BoardConfigCommon.mk

TARGET_BOOTLOADER_BOARD_NAME := arcfox
TARGET_OTA_ASSERT_DEVICE := arcfox

# Inner display: local:4630947043778501763, port 131, 1080x2640, density 420.
# Cover display: local:4630947043778501764, port 132, 1080x1272, density 360.
# Both report type INTERNAL on Android 16; on Android 14 the cover reported
# EXTERNAL / "HDMI Screen". See fold/ for the routing config.
TARGET_SCREEN_WIDTH := 1080
TARGET_SCREEN_HEIGHT := 2640
TARGET_SCREEN_DENSITY := 420

# Recovery fstab. Without this, build/make/core/Makefile silently sets
# build_ota_package := false (the `ifeq ($(recovery_fstab),)` gate), so
# INTERNAL_OTA_PACKAGE_TARGET is empty and LineageOS's bacon target then fails
# with "ln: cannot create hard link ... No such file or directory" while trying
# to link a zip that was never generated. The error names the zip, not the fstab.
#
# Taken verbatim from the shipping firmware's /vendor/etc/fstab.qcom.
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.qcom

TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888

-include vendor/motorola/arcfox/BoardConfigVendor.mk
