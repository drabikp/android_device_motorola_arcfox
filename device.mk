# Device makefile for Motorola razr 50 ultra / razr+ 2024 (arcfox).

LOCAL_PATH := device/motorola/arcfox

# Inherit the SM8635 common tree.
$(call inherit-product, device/motorola/sm8635-common/common.mk)

# Screen density. Inner panel is 420dpi; the cover panel is 360dpi and is
# handled per-display in fold/display_id_4630947043778501764.xml.
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := 420dpi
PRODUCT_AAPT_PREBUILT_DPI := xxxhdpi xxhdpi xhdpi hdpi

PRODUCT_SOONG_NAMESPACES += $(LOCAL_PATH)

# DO build vendor_boot.img. This was previously false: building it needs a
# vendor_ramdisk staging dir, and without one image assembly panics with
#   "lstat out/target/product/arcfox/vendor_ramdisk: no such file".
# The staging dir is now populated from BOARD_VENDOR_RAMDISK_KERNEL_MODULES in
# sm8635-common/BoardConfigCommon.mk (Motorola's 282 prebuilt .ko lifted out of
# stock's vendor_ramdisk, with stock's modules.load to fix load order), so the
# panic no longer applies.
#
# Why it matters: first-stage init reads its fstab and loads its modules from
# vendor_boot's ramdisk. Shipping STOCK vendor_boot meant LineageOS's init (from
# our init_boot) was being driven by Motorola's first-stage layout. That is the
# leading suspect for the remaining first-stage-init failure, and no shipping
# LineageOS device does it -- zeekr builds its own vendor_boot.
PRODUCT_BUILD_VENDOR_BOOT_IMAGE := true

# --- Fold -------------------------------------------------------------------
# Destination directories are NOT interchangeable. device_state_configuration
# goes to /vendor/etc/devicestate (where stock keeps it, verified on-device);
# the display files go to /vendor/etc/displayconfig, a directory stock does NOT
# have — arcfox ships no displayconfig at all, so the port creates it.
#
# The display_id_*.xml filenames encode the display address and must match
# `dumpsys display`. arcfox: ...763 inner, ...764 outer. zeekr uses ...762/...763,
# so its filenames land on the wrong panel here.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/fold/device_state_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/devicestate/device_state_configuration.xml \
    $(LOCAL_PATH)/fold/display_layout_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/displayconfig/display_layout_configuration.xml \
    $(LOCAL_PATH)/fold/display_id_4630947043778501763.xml:$(TARGET_COPY_OUT_VENDOR)/etc/displayconfig/display_id_4630947043778501763.xml \
    $(LOCAL_PATH)/fold/display_id_4630947043778501764.xml:$(TARGET_COPY_OUT_VENDOR)/etc/displayconfig/display_id_4630947043778501764.xml

# Hinge angle feature. arcfox exposes both android.sensor.hinge_angle and
# Motorola's com.motorola.sensor.hinge_posture; this declares the standard one.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.sensor.hinge_angle.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.hinge_angle.xml

# Overlay carrying config_foldedDeviceStates / halfFolded / open. Required in
# addition to the PROPERTY_FOLDABLE_* declarations in the device-state XML:
# both mechanisms are live in 23.2 and the legacy arrays are still read across
# frameworks/base.
PRODUCT_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay-lineage

# --- Recovery USB -----------------------------------------------------------
# Binds the USB gadget to a UDC in recovery so adb/sideload works. Without this
# the device renders recovery fine but never enumerates on USB.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/init.recovery.qcom.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.qcom.rc

# --- fstab ------------------------------------------------------------------
# rootdir/etc/fstab.qcom existed in the tree from the start but was never
# installed anywhere, so the built vendor image had NO /vendor/etc/fstab.qcom.
# Confirmed by mounting vendor_a from TWRP on the device: `ls /vendor/etc/fstab*`
# -> No such file or directory.
#
# First-stage mount survives that, because first-stage init reads its fstab from
# vendor_boot's ramdisk (/first_stage_ramdisk/fstab.qcom) and we ship stock's
# vendor_boot unmodified. SECOND-stage init reads /vendor/etc/fstab.<hardware>,
# and without it cannot mount /data, /metadata, /mnt/vendor/persist or
# /vendor/firmware_mnt. init gives up before console, adb or logging exist.
#
# Symptom this explains: hangs at the Motorola logo, then resets to the
# bootloader, burning one A/B retry, with nothing written to any log partition.
# The bootloader's own log (logfs -> Log<N>.txt) shows a clean handoff to the
# kernel, which rules out AVB and the boot images themselves.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.qcom:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.qcom

# --- vendor mount points ----------------------------------------------------
# The fstab mounts four physical partitions onto directories INSIDE vendor:
#   /vendor/firmware_mnt <- modem      wait,slotselect
#   /vendor/dsp          <- dsp        wait,slotselect
#   /vendor/bt_firmware  <- bluetooth  wait,slotselect
#   /vendor/fsg          <- fsg        wait,slotselect
# Stock's vendor image ships these as empty directories. Ours did not have them
# at all (confirmed: 1,394 files vs stock's 3,021, and every one of these
# top-level dirs absent), so all four mounts target a non-existent path. They
# are blocking `wait` mounts, and the kernel cmdline points
# firmware_class.path at /vendor/firmware_mnt/image, so the modem/DSP firmware
# is unreachable too.
#
# This was isolated by bisecting super: all-stock boots, all-stock + our dlkm
# boots, but swapping in OUR vendor.img fails -- and fails fast (~56s to
# bootloader) rather than hanging, which is what a failed mount_all looks like.
#
# PRODUCT_COPY_FILES cannot create an empty directory, so each mount point gets
# a stub file. The subsequent mount shadows it, exactly as on stock.
# NOTE: PRODUCT_COPY_FILES CANNOT be used for this. Android 16's soong
# filesystem generator rejects installing into a new top-level vendor directory:
#   error: module "vendor-..._rootdir_mountpoints_firmware_mnt-vendor_firmware_mnt-0"
#          ... Path is outside directory: ../firmware_mnt
# Tried both a hidden .keep and a plain file, and mirrored source dirs -- same
# error every time. The directories are currently injected into the staging tree
# by hand (see workspace/inject-vendor-mountpoints.sh) before the image is built.
# A proper fix probably needs a soong module or an fs_config entry.

# The SAME fstab also has to land in vendor_boot's ramdisk, because that is
# where FIRST-stage init reads it from (/first_stage_ramdisk/fstab.qcom).
# Previously we shipped stock vendor_boot, so first-stage silently used
# Motorola's copy; now that we build vendor_boot we must provide it ourselves,
# or first-stage init has no fstab at all.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.qcom:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.qcom

# --- Boot logger (DIAGNOSTIC — remove before publishing) ---------------------
# This device has no obtainable kernel log: ramoops is zeroed by the bootloader
# every boot, /proc/last_kmsg is absent, kpan/ramdump are empty and
# androidboot.console=0. The bootloader's own logfs log stops at the kernel
# handoff, so everything after that has been invisible all session.
#
# The failure is a SOFTWARE reset -- the bootloader reports "PM: Reset by
# PSHOLD", WARM_RESET_REASON1 "SOFT" -- about 328s in, which means init runs for
# minutes before giving up. So a userspace logger works where every kernel-level
# approach failed. It writes to the raw `kpan` partition, deliberately not a
# filesystem, because /data and /metadata are themselves suspect.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/logger/arcfox-logger.sh:$(TARGET_COPY_OUT_SYSTEM)/bin/arcfox-logger.sh \
    $(LOCAL_PATH)/logger/arcfox-logger.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/arcfox-logger.rc

# --- Blobs ------------------------------------------------------------------
$(call inherit-product-if-exists, vendor/motorola/arcfox/arcfox-vendor.mk)
