#!/system/bin/sh
# arcfox-logger — dump boot logs somewhere readable from TWRP after a failed boot.
#
# WHY: this device exposes NO kernel log path. pstore/ramoops is zeroed by the
# bootloader every boot, /proc/last_kmsg does not exist, kpan and ramdump are
# empty, and androidboot.console=0. The only boot-time log is the bootloader's
# own (logfs), which stops at the kernel handoff.
#
# But the failure is a SOFTWARE reset (bootloader reports "Reset by PSHOLD",
# WARM_RESET_REASON1 "SOFT") ~328s in, so init runs for minutes before giving
# up. That is plenty of time for a userspace logger.
#
# Target is the raw `kpan` partition (8 MiB, verified empty) rather than a
# filesystem, because /data and /metadata may be exactly what is broken.
#
# LAYOUT (this matters — see the two bugs below):
#   kpan[0    .. 4MiB)  EARLY snapshot, written ONCE at iteration 0, never again
#   kpan[4MiB .. 8MiB)  LATE  snapshot, rewritten every iteration
#
# Bug 1 this fixes — TRUNCATION. The previous version captured only
# `dmesg | tail -100` and `logcat | tail -250`, sampled at ~91s uptime. init
# logs to the KERNEL ring buffer, not to logd, so init's messages reach us only
# via dmesg; `tail -100` at 91s covered uptime ~176-186s worth of a repeating
# 1Hz message and nothing else. Every early_hal-era line — the entire window in
# which the keymint HAL would start, succeed or abort — was cut off. The
# conclusion drawn from that log ("no init lines for keymint, so it never
# started") was an artifact of the tail, not a finding.
#
# Bug 2 this fixes — STALE TAIL. `dd conv=notrunc` writes only as many bytes as
# the input has. A shorter write leaves the previous, longer record's tail in
# place, so the harvested file was a SPLICE of two different boots: header and
# logcat from the current one, dmesg tail from an older one. That is how a log
# headed "iteration 17, uptime 91.66" came to carry dmesg timestamps of 186s.
# The partition is now zeroed before first use.
#
# Bug 3 this fixes — RING-BUFFER WRAP. The kernel ring buffer is finite and
# "Too many pending control messages" repeats at 1Hz, so by the time a late
# iteration runs, early boot has been overwritten. The EARLY snapshot is taken
# at the first opportunity and never touched again, so it survives the flood.
P=/dev/block/by-name/kpan
T=/dev/arcfox-log.txt
HALF=1024                       # 1024 * 4096 = 4 MiB, the offset of LATE
CAP=4000000                     # keep each snapshot under its 4 MiB slot

# After this many 5s iterations, give up and reboot to the BOOTLOADER. Without
# this the phone sits alive-but-unreachable (no adb, no MTP, no reset) and every
# test iteration costs a manual power-cycle. Rebooting ourselves makes the whole
# build->flash->test->harvest loop unattended. The log is already on kpan, which
# survives the reboot.
GIVE_UP_AFTER=18     # 18 * 5s = ~90s past post-fs (was 36; the cycle's
                     # monitor window is 400s and we must fire well inside it)

# Zero the whole partition first, so nothing we read back can be a leftover of
# an earlier boot. 8 MiB, costs well under a second.
dd if=/dev/zero of="$P" bs=1M count=8 2>/dev/null
sync

# Give logd as much room as we can. Default is small enough that early boot is
# already gone by the time anything reads it. Harmless if logd is not up yet.
logcat -G 16M 2>/dev/null

# --- EARLY snapshot: taken now, written once, never overwritten --------------
# This is the one that matters. It is the only view of the window in which the
# early_hal services (keymint among them) are started.
{
    echo "===== arcfox EARLY snapshot, uptime $(cat /proc/uptime 2>/dev/null) ====="
    echo "--- FULL dmesg (NOT tailed) ---"
    dmesg 2>/dev/null
    echo "--- FULL logcat, security/HAL chain, unfiltered by tail ---"
    logcat -b all -d 2>/dev/null | grep -iE \
        "init:|avc:|denied|keymint|qseecom|keystore|weaver|gatekeeper|strongbox|tee|vold|servicemanager|hwservicemanager|vintf|SIGABRT|Check failed"
    echo "--- FULL logcat, everything ---"
    logcat -b all -d 2>/dev/null
} 2>/dev/null | head -c "$CAP" > "$T"
dd if="$T" of="$P" bs=4096 conv=notrunc,sync 2>/dev/null
sync

i=0
while [ "$i" -lt 200 ]; do
    if [ "$i" -ge "$GIVE_UP_AFTER" ] && [ ! -e /dev/.arcfox_booted ]; then
        # If the boot had completed, sys.boot_completed would be 1 and we would
        # not be here. Park in the bootloader so the host can collect the log.
        sync
        # Try several routes -- `reboot bootloader` has to write the
        # bootonce-bootloader command into the misc partition via
        # /dev/block/bootdevice/by-name/misc, which is exactly the path that may
        # be broken. sys.powerctl goes through init instead, and sysrq is a last
        # resort that needs nothing from userspace.
        setprop sys.powerctl reboot,bootloader
        sleep 10
        /system/bin/reboot bootloader
        sleep 10
        echo b > /proc/sysrq-trigger
        sleep 30
    fi
    # --- LATE snapshot: rolling, written into the second half of kpan --------
    {
        echo "===== arcfox LATE snapshot, iteration $i, uptime $(cat /proc/uptime 2>/dev/null) ====="
        echo "--- init/service failures and SELinux denials ---"
        logcat -b all -d 2>/dev/null | grep -iE \
            "init:|avc:|denied|keymint|qseecom|keystore|weaver|gatekeeper|strongbox|tee|vold|Service |crash|fatal|cannot |failed" \
            | tail -400
        echo "--- last 200 lines of everything ---"
        logcat -b all -d 2>/dev/null | tail -200
        echo "--- dmesg tail ---"
        dmesg 2>/dev/null | tail -200
    } 2>/dev/null | head -c "$CAP" > "$T"
    dd if="$T" of="$P" bs=4096 seek="$HALF" conv=notrunc,sync 2>/dev/null
    [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && touch /dev/.arcfox_booted
    sleep 5
    i=$((i + 1))
done
