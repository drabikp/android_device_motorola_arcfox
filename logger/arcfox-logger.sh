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
# STORE: the `ramdump` partition, 128 MiB, verified all-zero (the whole 128 MiB
# reads back as zeros, so nothing is being clobbered). kpan is only 8 MiB, which
# forced every snapshot to be tailed -- and the tailing is what hid the original
# root cause for two days. 128 MiB is enough to keep every sample in full.
#
# LAYOUT: fixed 4 MiB slots, so nothing can splice into anything else.
#   slot 0        EARLY snapshot, written once, at the first opportunity
#   slot 1+i      iteration i, written in full -- a TIMELINE, not just a last
#                 sample. This is the point: a service can be alive and silent
#                 for 90s (keymint-qti does exactly that) and only a series of
#                 snapshots shows when it stops making progress.
#
# kpan is still written with the EARLY snapshot as a fallback, in case the
# bootloader turns out to touch ramdump on some path we have not exercised.
P=/dev/block/by-name/ramdump
FALLBACK=/dev/block/by-name/kpan
T=/dev/arcfox-log.txt
SLOT=1024                       # 1024 * 4096 = 4 MiB per slot
CAP=4000000                     # keep each snapshot inside its slot

# After this many 5s iterations, give up and reboot to the BOOTLOADER. Without
# this the phone sits alive-but-unreachable (no adb, no MTP, no reset) and every
# test iteration costs a manual power-cycle. Rebooting ourselves makes the whole
# build->flash->test->harvest loop unattended. The log is already on kpan, which
# survives the reboot.
GIVE_UP_AFTER=18     # 18 * 5s = ~90s past post-fs (was 36; the cycle's
                     # monitor window is 400s and we must fire well inside it)

# Zero both stores first, so nothing we read back can be a leftover of an
# earlier boot. (This is not paranoia: `dd conv=notrunc` writes only as many
# bytes as the input has, so a shorter record used to leave the previous,
# longer one's tail in place and the harvested file was a splice of two boots.)
dd if=/dev/zero of="$P" bs=1M count=128 2>/dev/null
dd if=/dev/zero of="$FALLBACK" bs=1M count=8 2>/dev/null
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
dd if="$T" of="$FALLBACK" bs=4096 conv=notrunc,sync 2>/dev/null
sync

# 128 MiB / 4 MiB = 32 slots; slot 0 is EARLY, so iterations 0..30 fit. Stop
# there rather than dd'ing past the end of the partition.
i=0
while [ "$i" -lt 31 ]; do
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
    # --- iteration snapshot, in full, into its own slot ---------------------
    #
    # Nothing here is tailed. `logcat -G 16M` keeps the whole boot in the
    # buffer, and each iteration gets its own 4 MiB slot, so this is a complete
    # record of every sample rather than a single surviving one.
    {
        echo "===== arcfox snapshot, iteration $i, uptime $(cat /proc/uptime 2>/dev/null) ====="
        echo "--- init/service failures and SELinux denials (FULL) ---"
        logcat -b all -d 2>/dev/null | grep -iE \
            "init:|avc:|denied|keymint|qseecom|keystore|weaver|gatekeeper|strongbox|tee|vold|Service |crash|fatal|cannot |failed"
        # --- process forensics --------------------------------------------
        # keymint-qti is ALIVE and SILENT: three TimedRetryForwarder_release
        # lines at 2.6s and then nothing for 90s, no crash, no denial, and it
        # never reaches addService. Logs cannot say why, because it is not
        # logging -- it is blocked. So ask the kernel instead: wchan/syscall/
        # stack say where it is stuck, and /proc/PID/maps says which
        # keymint-V*-ndk.so it actually loaded (the V3-vs-V4 question that the
        # ELF alone cannot settle, since the ABI break is at runtime).
        echo "--- process forensics: keymint / qseecomd / vold / keystore2 ---"
        for p in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
            c=$(cat /proc/$p/cmdline 2>/dev/null | tr -d '\000')
            case "$c" in
                *keymint*|*qseecomd*|*vold*|*keystore2*|*qseecom@1.0*)
                    echo "== pid $p  $c"
                    echo "   state:   $(awk '/^State/{print $2,$3}' /proc/$p/status 2>/dev/null)"
                    echo "   wchan:   $(cat /proc/$p/wchan 2>/dev/null)"
                    echo "   syscall: $(cat /proc/$p/syscall 2>/dev/null)"
                    echo "   threads:"
                    for t in /proc/$p/task/*; do
                        [ -d "$t" ] || continue
                        echo "     tid $(basename $t) state=$(awk '/^State/{print $2}' $t/status 2>/dev/null) wchan=$(cat $t/wchan 2>/dev/null) syscall=$(cat $t/syscall 2>/dev/null | cut -d' ' -f1)"
                    done
                    echo "   kernel stack:"
                    cat /proc/$p/stack 2>/dev/null | head -25
                    echo "   security/AIDL libs mapped:"
                    grep -oE '/[^ ]*(keymint|rkp|secureclock|sharedsecret|qtikeymint|QSEECom|tpa|ops)[^ ]*\.so' /proc/$p/maps 2>/dev/null | sort -u
                    echo "   open fds:"
                    ls -l /proc/$p/fd 2>/dev/null | sed 's/^.* -> /     -> /' | sort | uniq -c | head -25
                    ;;
            esac
        done
        echo "--- FULL dmesg ---"
        dmesg 2>/dev/null
        # The unfiltered logcat is TAILED, unlike the filtered section above.
        # Once the boot got past late-fs the logs grew enough that snapshots
        # from iteration 5 on hit the 4 MiB slot cap exactly and were cut off
        # mid-file -- losing the END of each snapshot, which is the newest and
        # most interesting part. The filtered section and dmesg are complete;
        # this one only needs enough context around them.
        echo "--- logcat, everything (last 4000 lines) ---"
        logcat -b all -d 2>/dev/null | tail -4000
    } 2>/dev/null | head -c "$CAP" > "$T"
    dd if="$T" of="$P" bs=4096 seek="$(( SLOT * (i + 1) ))" conv=notrunc,sync 2>/dev/null
    [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && touch /dev/.arcfox_booted
    sleep 5
    i=$((i + 1))
done
