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

# Boot animation on BOTH panels, which is how stock stops the cover panel from
# sitting on the bootloader splash.
# =============================================================================
# Symptom without this: after a reboot with the phone open, the cover panel keeps
# showing the Motorola boot logo and its digitiser stays powered, until the first
# physical fold. Nothing in the framework ever clears it, and the reason is a
# three-layer agreement that the panel is already off while the bootloader has it
# lit:
#
#   DisplayManager  mDisplayStates[6] UNKNOWN -> OFF
#   SurfaceFlinger  DisplayDevice::mPowerMode  OFF from construction
#   SDM             DisplayBase::state_        kStateOff from construction
#
# so the single STATE_OFF the framework does emit after PHASE_BOOT_COMPLETED is
# swallowed by SurfaceFlinger's `currentMode == mode` early return, and no DRM
# commit ever reaches DSI-2. An OFF cannot blank a panel that no software layer
# has ever seen as ON; only a real transition can, which is exactly why one fold
# cycle fixes it by hand.
#
# HOW STOCK SOLVES IT: it does not blank the panel, it DRAWS on it. Motorola runs
# a second boot animation there, with their own markers still in the file --
# system/etc/init/bootanim.rc:
#     # BEGIN Motorola, caijh, 06/27/2023, IKSWT-157000
#     service bootanim-cli /system/bin/bootanimation --cli
# backed by a patched SurfaceFlinger carrying `Start cli bootanim...` and
# persist.sys.sf.force_cli_display_index, neither of which exists in AOSP.
#
# We need no patches, because AOSP grew the same capability for foldables
# independently. BootAnimation::initDisplaysAndSurfaces() enumerates every
# physical display and then throws all but the first away:
#     if (!com::android::graphics::bootanimation::flags::multidisplay()) {
#         displayIds.erase(displayIds.begin() + 1, displayIds.end());
#     }
# The flag is is_fixed_read_only, so it is a build-time decision, and LineageOS
# already ships the value set that turns it on
# (vendor/lineage/release/aconfig/bp4a/com.android.graphics.bootanimation.flags/)
# gated behind exactly this soong config variable. No device tree in this tree
# sets it, so it has always been off.
#
# Why this is expected to fix the power state too, not just paint over it:
# SurfaceFlinger::initializeDisplays() powers ON every display in
# mPhysicalDisplays, and compositing to the cover panel keeps it genuinely ON.
# The framework's later STATE_OFF then differs from the cached mode, so it is NOT
# swallowed -- it becomes a real transition, the panel blanks, and the DRM panel
# notifier suspends the cover digitiser with it. That is the same shape as the
# manual fold cycle, minus the fold.
$(call soong_config_set_bool,bootanimation,multidisplay,true)

-include vendor/motorola/arcfox/BoardConfigVendor.mk
