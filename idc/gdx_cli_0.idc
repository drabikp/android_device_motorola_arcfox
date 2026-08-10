# Input device configuration for the COVER panel touchscreen (Goodix, gdx_cli_0).
#
# Verbatim from stock: /vendor/usr/idc/gdx_cli_0.idc in W1UXS36H. Kept as a
# device-tree file rather than a blob only because it is three lines of text and
# was never part of the extracted set; the content is Motorola's, unmodified.
#
# WHY THIS MATTERS. Without it neither touchscreen has a display association, and
# TouchInputMapper then falls through to its last rule: pick a viewport by type
# INTERNAL. getDisplayViewportByType() explicitly prefers the viewport whose
# displayId is DEFAULT, and BOTH panels on this device are type INTERNAL. So the
# cover digitiser bound to the INNER display and its touches were injected into
# the inner UI -- with the phone open, brushing the closed-side glass moved the
# pointer on the main screen.
#
# With touch.displayId set, the cover digitiser binds to the cover panel's own
# viewport. While the phone is open that viewport is reported isActive=false
# (the display is disabled by the OPENED layout), and TouchInputMapper puts a
# device whose viewport is inactive into DeviceMode::DISABLED. So the cover touch
# goes inert while open and live while folded, with no policy code and no
# per-state switching.
#
# device.internal = 0 is stock's value and is deliberate. It is NOT a claim that
# the panel is external -- it suppresses the built-in-display association that
# would otherwise be applied, leaving touch.displayId as the only binding.
#
# touch.wake = 0 keeps a stray touch on the closed-side glass from waking the
# device, which is the correct behaviour for a panel that is off.
#
# The stock tree also ships fts_ts.idc with the identical three lines: that is
# the same cover panel from a second digitiser supplier (Focaltech). This unit
# enumerates gdx_cli_0, so only this file is shipped. If a device ever shows
# fts_ts in `dumpsys input`, add the twin.
device.internal = 0
touch.wake = 0
touch.displayId = local:4630947043778501764
