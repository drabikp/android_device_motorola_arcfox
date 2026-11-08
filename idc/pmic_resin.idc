# Input device configuration for the volume down key (pmic_resin).
#
# Folded, the cover screen is on the back of the half that does NOT carry the
# volume rocker, turned 180 degrees from the inner panel. So the rocker is upside
# down relative to the cover's natural orientation: in cover portrait the UPPER key
# turned the volume DOWN (measured 2026-11-08, swap-on-rotation off). Stock handles
# this in its own services.jar and libinputreader (persist.sys.cli.keyswap).
#
# keyboard.volumeRotationOffset.port<N> tells KeyboardInputMapper (frameworks/native,
# arcfox-24.0) how far the keys are turned, in quarter turns, while display port N
# is the default display. Port 132 is the cover panel (local:4630947043778501764);
# the inner panel (port 131) needs no offset.
keyboard.volumeRotationOffset.port132 = 2
