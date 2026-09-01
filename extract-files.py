#!/usr/bin/env -S PYTHONPATH=../../../tools/extract-utils python3
#
# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Motorola razr 50 ultra / razr+ 2024 (arcfox), SM8635.
#
# Usage, per the LineageOS wiki (extracting_blobs_from_zips.html): this device
# has no rooted-adb path, because the shell SELinux domain cannot read most of
# /vendor and cannot see /vendor/firmware at all. Extract from the firmware
# instead:
#
#     ./extract-files.py ~/android/firmware/W1UXS36H/extracted
#
# blob_fixups starts EMPTY on purpose. Every entry in a mature tree (see
# peridot's, which is ~300 lines) was added in response to a specific build or
# boot failure. Adding speculative fixups hides real errors.

from extract_utils.fixups_blob import (
    blob_fixup,
    blob_fixups_user_type,
)
from extract_utils.fixups_lib import (
    lib_fixups,
    lib_fixups_user_type,
)
from extract_utils.main import (
    ExtractUtils,
    ExtractUtilsModule,
)

namespace_imports = [
    'device/motorola/sm8635-common',
    'vendor/motorola/sm8635-common',
    'hardware/qcom-caf/sm8650',
    'hardware/qcom-caf/wlan',
    'vendor/qcom/opensource/commonsys/display',
    'vendor/qcom/opensource/commonsys-intf/display',
    'vendor/qcom/opensource/dataservices',
    'vendor/qcom/opensource/display',
]

lib_fixups: lib_fixups_user_type = {
    **lib_fixups,
}

blob_fixups: blob_fixups_user_type = {
    # --- NO tinyxml2 FIXUP FOR motorola.hardware.sensorext-service --------------
    # ⚠️ There used to be a .replace_needed('libtinyxml2.so', 'libtinyxml2_1.so')
    # here. It was WRONG for this blob and it made the service SIGABRT four times
    # on every boot. Do not put it back. Measured 2026-09-01:
    #
    # The removed comment asserted "it was built against 10.x". That is false for
    # THIS binary -- it is built against 11.x. The offset of
    # tinyxml2::XMLElement::_rootAttribute is the discriminator, read straight out
    # of XMLElement::FindAttribute() in each library:
    #
    #   vendor/lib64/libtinyxml2_1.so   (10.x)  ldr x19, [x0, #0x68]
    #   system/lib64/libtinyxml2.so     (11.x)  ldr x19, [x0, #0x70]
    #
    # and the crashing instruction inside SensorExt::initAlsComp is
    #
    #   93 9c:  ldr x21, [x27, #0x70]     <- 11.x layout
    #   93 b4:  bl  __cfi_slowpath        <- checks x21's vtable, ABORTS
    #
    # Pointed at the 10.x library the blob reads _rootAttribute from a member that
    # is something else in that layout, hands the resulting non-object to
    # cross-DSO CFI, and libtinyxml2_1.so's __cfi_check aborts. The tombstone is
    # abort <- libtinyxml2_1.so <- SensorExt::initAlsComp <- ISensorExt_onTransact,
    # i.e. it dies servicing a binder call, so init restarts it, the caller retries,
    # and it settles only once the caller gives up -- which is why the service looks
    # alive afterwards while ALS compensation never initialises.
    #
    # ⚠️ The other justification in that comment was also wrong: it claimed stock's
    # vendor/lib64/libtinyxml2.so is a SYMLINK to libtinyxml2_1.so that extract_utils
    # drops. There is no such symlink in the W1UXS36H dump, and symlinks ARE
    # preserved there (vendor/lib64 has three: libEGL_adreno, libGLESv2_adreno,
    # libq3dtools_adreno). Unmodified, the blob binds the 11.x
    # vendor/lib64/libtinyxml2.so we already install -- AOSP's libtinyxml2 is
    # vendor_available and its symbol set is IDENTICAL to stock's
    # system/lib64/libtinyxml2.so (222 tinyxml2 symbols each; the 10.x _1 copy has
    # 190 and is missing the Unsigned64*/ChildElementCount/DeepCopy/ErrorStr APIs).
    #
    # The sm8635-common fixup is a DIFFERENT case and stays: those display blobs
    # really are 10.x. Before adding any blob to it, run the 0x68-vs-0x70 test above
    # on that blob rather than assuming the whole vendor image was built alike.
    # Motorola's camera stack links android.hardware.graphics.allocator V1,
    # but Android 16's libui pulls V2, and soong refuses a module that depends
    # on two versions of the same aidl_interface:
    #   "depends on multiple versions of the same aidl_interface:
    #    android.hardware.graphics.allocator-V1-ndk-source, ...-V2-ndk-source"
    # Rewrite the DT_NEEDED entry to V2. Same fix peridot applies to its camera
    # blobs. The 70 entries below were found by scanning the extracted blobs
    # for the V1 soname, not copied from another device.
    (
        'vendor/lib64/camera/com.mot.eeprom.mot_gt24p64e_ov32b40_eeprom.so',
        'vendor/lib64/camera/com.qti.ois.mot_dw9784.so',
        'vendor/lib64/camera/com.qti.sensor.mot_ov32b40.so',
        'vendor/lib64/camera/components/com.qti.node.aon.so',
        'vendor/lib64/camera/components/com.qti.node.depth.so',
        'vendor/lib64/camera/components/com.qti.node.dewarp.so',
        'vendor/lib64/camera/components/com.qti.node.eisv2.so',
        'vendor/lib64/camera/components/com.qti.node.eisv3.so',
        'vendor/lib64/camera/components/com.qti.node.gme.so',
        'vendor/lib64/camera/components/com.qti.node.gyrornn.so',
        'vendor/lib64/camera/components/com.qti.node.hdr10pgen.so',
        'vendor/lib64/camera/components/com.qti.node.hdr10phist.so',
        'vendor/lib64/camera/components/com.qti.node.ml.so',
        'vendor/lib64/camera/components/com.qti.node.mlinference.so',
        'vendor/lib64/camera/components/com.qti.node.swec.so',
        'vendor/lib64/camera/components/com.qti.node.swregistration.so',
        'vendor/lib64/camera/components/com.qti.stats.cnndriver.so',
        'vendor/lib64/camera/components/libdepthmapwrapper_secure.so',
        'vendor/lib64/com.qti.camx.chiiqutils.so',
        'vendor/lib64/com.qti.chiusecaseselector.so',
        'vendor/lib64/com.qti.feature2.anchorsync.so',
        'vendor/lib64/com.qti.feature2.arcrawpro.so',
        'vendor/lib64/com.qti.feature2.demux.so',
        'vendor/lib64/com.qti.feature2.derivedoffline.so',
        'vendor/lib64/com.qti.feature2.fusion.so',
        'vendor/lib64/com.qti.feature2.generic.so',
        'vendor/lib64/com.qti.feature2.hdr.so',
        'vendor/lib64/com.qti.feature2.mcreprocrt.so',
        'vendor/lib64/com.qti.feature2.memcpy.so',
        'vendor/lib64/com.qti.feature2.mfsr.so',
        'vendor/lib64/com.qti.feature2.ml.so',
        'vendor/lib64/com.qti.feature2.mux.so',
        'vendor/lib64/com.qti.feature2.qcfa.so',
        'vendor/lib64/com.qti.feature2.rawhdr.so',
        'vendor/lib64/com.qti.feature2.realtimeserializer.so',
        'vendor/lib64/com.qti.feature2.rt.so',
        'vendor/lib64/com.qti.feature2.rtmcx.so',
        'vendor/lib64/com.qti.feature2.serializer.so',
        'vendor/lib64/com.qti.feature2.statsregeneration.so',
        'vendor/lib64/com.qti.feature2.stub.so',
        'vendor/lib64/com.qti.feature2.swmf.so',
        'vendor/lib64/com.qti.qseeutils.so',
        'vendor/lib64/com.qualcomm.mcx.distortionmapper.so',
        'vendor/lib64/com.qualcomm.mcx.linearmapper.so',
        'vendor/lib64/com.qualcomm.mcx.policy.mfl.so',
        'vendor/lib64/com.qualcomm.qti.mcx.usecase.extension.so',
        'vendor/lib64/hw/camera.qcom.so',
        'vendor/lib64/hw/com.qti.chi.override.so',
        'vendor/lib64/libcamerapostproc.so',
        'vendor/lib64/libcamxhwnodecontext.so',
        'vendor/lib64/libcamxifestriping.so',
        'vendor/lib64/libcamximageformatutils.so',
        'vendor/lib64/libcommonchiutils.so',
        'vendor/lib64/libhme.so',
        'vendor/lib64/libipebpsstriping.so',
        'vendor/lib64/libipebpsstriping170.so',
        'vendor/lib64/libipebpsstriping480.so',
        'vendor/lib64/libjpege.so',
        'vendor/lib64/libmfec.so',
        'vendor/lib64/libmmcamera_bestats.so',
        'vendor/lib64/libmmcamera_lscv35.so',
        'vendor/lib64/libmmcamera_mfnr.so',
        'vendor/lib64/libmmcamera_mfnr_t4.so',
        'vendor/lib64/libmmcamera_pdpc.so',
        'vendor/lib64/libopestriping.so',
        'vendor/lib64/libtfestriping.so',
        'vendor/lib64/libubifocus.so',
        # Vidhance is Motorola's video stabiliser on arcfox, and CamX core here is
        # built with it (camera.qcom.sm8650.so: "Deferring %fx zoom to Vidhance",
        # "VIDHANCE: Reducing IFE residual crop"). These three CHI nodes carry the
        # EISv3 node inside them; without them the EIS usecase cannot be created:
        #   camxchinodewrapper.cpp:138 Failed to load Chi interface for
        #                              com.vidhance.node.preview
        #   camxnodefactory.cpp:164    Node type 255 is not supported or created
        #   chxextensionmodule.cpp:7623 CreateUsecaseObject failed  -> black camera
        # They were excluded for the allocator V1/V2 conflict, but that is exactly
        # what this fixup rewrites -- com.qti.node.eisv3.so has an identical
        # dependency shape and ships fine because it is already in this tuple. A
        # DT_NEEDED closure over the built vendor image shows the allocator is
        # their ONLY unsatisfied dependency.
        'vendor/lib64/camera/components/com.vidhance.node.gme.so',
        'vendor/lib64/camera/components/com.vidhance.node.preview.so',
        'vendor/lib64/camera/components/com.vidhance.node.video.so',
        'vendor/lib64/camera/components/libcamxevainterface.so',
        'vendor/lib64/vendor.qti.hardware.camera.aon-service-impl.so',
        'vendor/lib64/vendor.qti.hardware.camera.offlinecamera-service-impl.so',
        'vendor/lib64/vendor.qti.hardware.camera.postproc@1.0-service-impl.so',
    ): blob_fixup()
        .replace_needed(
            'android.hardware.graphics.allocator-V1-ndk.so',
            'android.hardware.graphics.allocator-V2-ndk.so'
    ),
}  # fmt: skip

# add_firmware_proprietary_file is deliberately OFF. It requires a
# proprietary-firmware.txt listing the radio-side partition images (modem,
# bluetooth, dsp, ...). Those live outside super.img and are not replaced by a
# LineageOS flash, so the stock ones already on the handset are used. Turn this
# on and author the list only if firmware ever needs to ship with the ROM.
module = ExtractUtilsModule(
    'arcfox',
    'motorola',
    blob_fixups=blob_fixups,
    lib_fixups=lib_fixups,
    namespace_imports=namespace_imports,
)

if __name__ == '__main__':
    utils = ExtractUtils.device_with_common(module, 'sm8635-common')
    utils.run()
