/*
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.arcfox.flipcalls;

import android.app.NotificationManager;
import android.hardware.devicestate.DeviceState;
import android.hardware.devicestate.DeviceStateManager;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.telecom.Call;
import android.telecom.CallAudioState;
import android.telecom.InCallService;
import android.telecom.TelecomManager;
import android.telecom.VideoProfile;
import android.util.Log;
import android.widget.Toast;

import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;

/**
 * Stock's flip call handling, rebuilt as a non-UI InCallService.
 *
 * <p>The rules are Motorola's, read from its Telecom.apk: CallsManager
 * (handleDeviceStateAction, handleAudioRoutingOnFlipOpenCloseAction,
 * answerCallOnStateChange, disconnectAllCalls, useSpeakerForCli),
 * CallAudioRouteController (the default route is the speakerphone while the
 * cover screen is active) and Call (the conference toast); and from the
 * services.jar side that feeds them (com.motorola.server.cli
 * .CliDisplayTransition). One deliberate difference: closing never ends an
 * emergency call; it is treated like the "continue call" setting instead, so
 * the call moves to the speakerphone rather than staying on a folded-shut
 * earpiece.
 *
 * <p>Telecom binds this only while calls exist, so the posture before the
 * first call is the callback's registration echo rather than history. An
 * opening that completes before that echo arrives counts as the starting
 * posture, not as an opening (stock's Telecom is always listening).
 */
@SuppressWarnings("deprecation") // CallAudioState/setAudioRoute: the route model stock decides on
public class FlipCallService extends InCallService {

    private static final String TAG = "ArcfoxFlipCalls";

    // Motorola's numbering, which only holds because fold/
    // device_state_configuration.xml ships stock's table unchanged; AOSP-style
    // fold configs (e.g. LineageOS zeekr) number their states differently.
    private static final int STATE_UNKNOWN = -1;
    private static final int STATE_CLOSED_HALL = 0;
    private static final int STATE_CLOSED = 1;
    private static final int STATE_TENT = 2;
    private static final int STATE_HALF_OPENED_QVD = 3;
    private static final int STATE_HALF_OPENED_MAIN = 4;
    private static final int STATE_OPENED = 5;
    private static final int STATE_OPENED_HALL = 6;

    // Stock acts on the posture the hinge settles in: services.jar
    // (CliDisplayTransition.notifyLidEvent) re-arms a 500 ms timer on every
    // change and broadcasts the state it was armed with.
    private static final long SETTLE_DELAY_MS = 500;
    // Opening through HALF_OPENED_MAIN within this long still counts as opening
    // from closed (CallsManager.wasTransitioningOnLaptopMode).
    private static final long LAPTOP_TRANSITION_MS = 2000;

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private DeviceStateManager mDeviceStateManager;

    /** Newest reported state, exactly as reported (OPENED_HALL kept). */
    private int mReportedState = STATE_UNKNOWN;
    /** What the armed settle timer will deliver, fixed when armed. */
    private int mArmedState = STATE_UNKNOWN;
    /** Last state acted on; stock's previousState. */
    private int mSettledState = STATE_UNKNOWN;
    /** Posture when the newest incoming call arrived; stock's initialState. */
    private int mInitialState = STATE_UNKNOWN;
    private boolean mInitialStatePending;
    private long mHalfOpenedSince = -1;
    private CallAudioState mLastAudioState;

    /** Calls seen ringing, so their move to ACTIVE can be recognised as an answer. */
    private final Set<Call> mRinging = new HashSet<>();
    /** Ringing calls that took the audio focus while the cover screen was active. */
    private final Set<Call> mRangOnCover = new HashSet<>();
    /** Calls added before the first posture report; decided on it. */
    private final Set<Call> mUndecided = new HashSet<>();
    /** Calls stock would have started on the speakerphone, not yet switched. */
    private final Set<Call> mSpeakerPending = new HashSet<>();
    /** Calls that can currently manage a conference. */
    private final Set<Call> mManagesConference = new HashSet<>();

    private final DeviceStateManager.DeviceStateCallback mDeviceStateCallback =
            new DeviceStateManager.DeviceStateCallback() {
                @Override
                public void onDeviceStateChanged(DeviceState state) {
                    onReportedState(state.getIdentifier());
                }
            };

    private final Runnable mSettle = () -> onSettledState(mArmedState);

    private final Call.Callback mCallCallback = new Call.Callback() {
        @Override
        public void onStateChanged(Call call, int state) {
            if (isRinging(call)) {
                if (mRinging.add(call)) {
                    noteRingStart(call);
                }
            } else if (mRinging.remove(call)) {
                mRangOnCover.remove(call);
                if (state == Call.STATE_ACTIVE && isCoverScreenActive()) {
                    // useSpeakerForCli, decided when an incoming call is answered.
                    mSpeakerPending.add(call);
                }
            }
            applyPendingSpeaker();
        }

        @Override
        public void onDetailsChanged(Call call, Call.Details details) {
            // Stock's Call.setConnectionCapabilities: gaining conference
            // management while the cover screen is active shows a toast.
            if (details.can(Call.Details.CAPABILITY_MANAGE_CONFERENCE)) {
                if (mManagesConference.add(call) && isCoverScreenActive()) {
                    showManageCallToast();
                }
            } else {
                mManagesConference.remove(call);
            }
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        mDeviceStateManager = getSystemService(DeviceStateManager.class);
        mDeviceStateManager.registerCallback(getMainExecutor(), mDeviceStateCallback);
    }

    @Override
    public void onDestroy() {
        mDeviceStateManager.unregisterCallback(mDeviceStateCallback);
        mHandler.removeCallbacks(mSettle);
        super.onDestroy();
    }

    @Override
    public void onCallAdded(Call call) {
        call.registerCallback(mCallCallback, mHandler);
        final Call.Details details = call.getDetails();
        final int state = details.getState();
        if (details.can(Call.Details.CAPABILITY_MANAGE_CONFERENCE)) {
            mManagesConference.add(call);
        }
        // Calls already established when we are (re)bound were decided before.
        final boolean isNew = state == Call.STATE_NEW || state == Call.STATE_CONNECTING
                || state == Call.STATE_SELECT_PHONE_ACCOUNT || state == Call.STATE_DIALING
                || isRinging(call);
        if (isNew && details.getCallDirection() == Call.Details.DIRECTION_INCOMING) {
            // Stock records initialState in processIncomingCallIntent only.
            if (mReportedState == STATE_UNKNOWN) {
                mInitialStatePending = true;
            } else {
                mInitialState = settleValue(mReportedState);
            }
        }
        if (mReportedState == STATE_UNKNOWN) {
            mUndecided.add(call);
        } else {
            decideOnAdd(call, isNew);
        }
        if (isRinging(call)) {
            mRinging.add(call);
        }
        applyPendingSpeaker();
    }

    @Override
    public void onCallRemoved(Call call) {
        call.unregisterCallback(mCallCallback);
        mRinging.remove(call);
        mRangOnCover.remove(call);
        mUndecided.remove(call);
        mSpeakerPending.remove(call);
        mManagesConference.remove(call);
    }

    @Override
    public void onCallAudioStateChanged(CallAudioState audioState) {
        final CallAudioState previous = mLastAudioState;
        mLastAudioState = audioState;
        if (previous != null && audioState != null && isCoverScreenActive()
                && audioState.getRoute() == CallAudioState.ROUTE_EARPIECE) {
            // A headset or Bluetooth device went away. Stock falls back to its
            // default route, which is the speakerphone while the cover screen
            // is active (CallAudioRouteController.getPreferredAudioRouteFromDefault).
            final int gone = previous.getRoute();
            if ((gone == CallAudioState.ROUTE_BLUETOOTH
                    || gone == CallAudioState.ROUTE_WIRED_HEADSET)
                    && (audioState.getSupportedRouteMask() & gone) == 0) {
                final Call call = possiblyHeldForegroundCall();
                if (call != null && call.getDetails().getState() == Call.STATE_RINGING) {
                    mRangOnCover.add(call);
                } else if (call != null) {
                    Log.i(TAG, "headset gone with the cover screen active: speakerphone");
                    setAudioRoute(CallAudioState.ROUTE_SPEAKER);
                }
            }
        }
        // On a (re)bind Telecom sends the calls before the audio state.
        applyPendingSpeaker();
    }

    /** Decisions stock takes when a call is created, once the posture is known. */
    private void decideOnAdd(Call call, boolean isNew) {
        if (isNew && call.getDetails().getCallDirection() == Call.Details.DIRECTION_OUTGOING
                && isCoverScreenActive()) {
            // useSpeakerForCli, decided when an outgoing call is created.
            mSpeakerPending.add(call);
        }
        if (isRinging(call)) {
            noteRingStart(call);
        }
    }

    /**
     * A call that rings with no call holding the audio takes the ringing
     * focus, and stock routes that focus to its default route: the
     * speakerphone while the cover screen is active. Telecom here keeps the
     * earpiece, so remember it; closing must then not decline the call
     * (stock declines only on the earpiece).
     */
    private void noteRingStart(Call call) {
        if (activeDialingOrConnectingCall() == null && isCoverScreenActive()) {
            mRangOnCover.add(call);
        }
    }

    private void onReportedState(int state) {
        final int previous = mReportedState;
        mReportedState = state;
        Log.d(TAG, "device state " + state + (previous == STATE_UNKNOWN ? " (current)" : ""));
        if (previous == STATE_UNKNOWN) {
            // The registration echo: where the phone already was, not a movement.
            mSettledState = settleValue(state);
            if (mInitialStatePending) {
                mInitialState = mSettledState;
                mInitialStatePending = false;
            }
            for (Call call : mUndecided) {
                final int callState = call.getDetails().getState();
                decideOnAdd(call, callState != Call.STATE_ACTIVE
                        && callState != Call.STATE_HOLDING);
            }
            mUndecided.clear();
            applyPendingSpeaker();
            return;
        }
        // Two moves for which services.jar neither arms nor re-arms its
        // broadcast, so the pending one (if any) still goes out unchanged:
        // a lid bouncing from CLOSED_HALL back to CLOSED while being shut, and
        // OPENED <-> OPENED_HALL, the same open posture reported two ways.
        if ((previous == STATE_CLOSED_HALL && state == STATE_CLOSED)
                || (previous == STATE_OPENED && state == STATE_OPENED_HALL)
                || (previous == STATE_OPENED_HALL && state == STATE_OPENED)) {
            return;
        }
        mArmedState = settleValue(state);
        mHandler.removeCallbacks(mSettle);
        mHandler.postDelayed(mSettle, SETTLE_DELAY_MS);
    }

    private void onSettledState(int state) {
        final int previous = mSettledState;
        mSettledState = state;
        if (getCalls().isEmpty()) {
            return;
        }
        final Call foreground = foregroundCall();
        if (foreground != null && (isSelfManaged(foreground) || isExternal(foreground))) {
            return;
        }
        Log.i(TAG, "posture " + previous + " -> " + state);

        switch (state) {
            case STATE_CLOSED_HALL:
                onClosed(previous);
                break;
            case STATE_CLOSED:
            case STATE_TENT:
            case STATE_HALF_OPENED_QVD:
                // Folded part-way from open, e.g. propped on a table.
                if (wasOpen(previous)) {
                    routeForFlip(/* closed= */ true);
                }
                break;
            case STATE_HALF_OPENED_MAIN:
                if (!wasOpen(previous)) {
                    mHalfOpenedSince = SystemClock.elapsedRealtime();
                }
                break;
            case STATE_OPENED:
                onOpened(previous);
                break;
            default:
                Log.w(TAG, "unknown device state " + state);
                break;
        }
    }

    private void onClosed(int previous) {
        final boolean emergency = inEmergencyCall();
        if (emergency || !FlipCallSettings.endCallOnClose(this)) {
            if (emergency) {
                Log.i(TAG, "closed during an emergency call: keeping it");
            }
            if (wasOpen(previous)) {
                routeForFlip(/* closed= */ true);
            }
            final Call foreground = foregroundCall();
            if (foreground != null
                    && foreground.getDetails().can(Call.Details.CAPABILITY_MANAGE_CONFERENCE)) {
                showManageCallToast();
            }
            mInitialState = STATE_CLOSED_HALL;
            return;
        }
        // Only a call held to the ear ends: on the speakerphone, a headset or
        // Bluetooth, closing is just putting the phone down.
        int route = currentRoute();
        final Call foreground = possiblyHeldForegroundCall();
        if (route == CallAudioState.ROUTE_EARPIECE && foreground != null
                && mRangOnCover.contains(foreground)) {
            route = CallAudioState.ROUTE_SPEAKER; // where stock rings it, see noteRingStart
        }
        if (route != CallAudioState.ROUTE_EARPIECE) {
            Log.i(TAG, "closed, call kept on " + CallAudioState.audioRouteToString(route));
            return;
        }
        Log.i(TAG, "closed on the earpiece: ending calls");
        for (Call call : getCalls()) {
            final int state = call.getDetails().getState();
            if (state == Call.STATE_RINGING) {
                call.reject(false, null);
            } else if (state != Call.STATE_DISCONNECTING && state != Call.STATE_DISCONNECTED) {
                call.disconnect();
            }
        }
    }

    private void onOpened(int previous) {
        if (!wasOpen(previous) || isOpeningThroughHalfOpened(previous)) {
            routeForFlip(/* closed= */ false);
        }
        final Call ringing = firstRingingCall();
        if (ringing != null && shouldAnswerOnOpen()) {
            Log.i(TAG, "opened while ringing: answering");
            ringing.answer(ringing.getDetails().getVideoState());
        }
    }

    private boolean shouldAnswerOnOpen() {
        // A call that arrived while the phone stood propped open is not
        // answered by opening it the rest of the way.
        if (mInitialState == STATE_TENT || mInitialState == STATE_HALF_OPENED_QVD
                || mInitialState == STATE_HALF_OPENED_MAIN) {
            return false;
        }
        // Nor one that Do Not Disturb keeps out of sight: the user may not know
        // it is ringing.
        if (notificationsSuppressed()) {
            return false;
        }
        return FlipCallSettings.answerOnOpen(this);
    }

    private static boolean wasOpen(int state) {
        return state == STATE_OPENED || state == STATE_HALF_OPENED_MAIN;
    }

    private boolean isOpeningThroughHalfOpened(int previous) {
        return previous == STATE_HALF_OPENED_MAIN && mHalfOpenedSince >= 0
                && SystemClock.elapsedRealtime() - mHalfOpenedSince <= LAPTOP_TRANSITION_MS;
    }

    /**
     * Stock's MotorolaSettings lid_state == 0: the cover screen is the active
     * display. Our display layout makes it so in every state up to
     * HALF_OPENED_QVD.
     */
    private boolean isCoverScreenActive() {
        return mReportedState != STATE_UNKNOWN
                && settleValue(mReportedState) <= STATE_HALF_OPENED_QVD;
    }

    /**
     * Stock's handleAudioRoutingOnFlipOpenCloseAction: closing moves the call
     * to the speakerphone; opening moves voice back to the earpiece and video
     * to the speakerphone. Never while a headset or Bluetooth carries it, and
     * not while the call the audio follows is still ringing.
     */
    private void routeForFlip(boolean closed) {
        final Call call = possiblyHeldForegroundCall();
        if (call == null || call.getDetails().getState() == Call.STATE_RINGING
                || headsetOrBluetoothInUse()) {
            return;
        }
        if (closed) {
            Log.i(TAG, "folded during a call: speakerphone");
            setAudioRoute(CallAudioState.ROUTE_SPEAKER);
            return;
        }
        if (hasEmergencyRttCall()) {
            return;
        }
        if (VideoProfile.isVideo(call.getDetails().getVideoState())) {
            setAudioRoute(CallAudioState.ROUTE_SPEAKER);
        } else {
            Log.i(TAG, "opened during a call: earpiece");
            setAudioRoute(CallAudioState.ROUTE_EARPIECE);
        }
    }

    /**
     * Stock's useSpeakerForCli, which marks a call to start on the
     * speakerphone. Applied once the call is audible and Telecom has told us
     * the audio state.
     */
    private void applyPendingSpeaker() {
        if (getCallAudioState() == null) {
            return;
        }
        for (Iterator<Call> it = mSpeakerPending.iterator(); it.hasNext(); ) {
            final Call call = it.next();
            final int state = call.getDetails().getState();
            if (state != Call.STATE_DIALING && state != Call.STATE_ACTIVE) {
                continue;
            }
            it.remove();
            if (headsetOrBluetoothPresent()) {
                continue;
            }
            Log.i(TAG, "call " + (state == Call.STATE_DIALING ? "placed" : "answered")
                    + " on the cover screen: speakerphone");
            setAudioRoute(CallAudioState.ROUTE_SPEAKER);
        }
    }

    /**
     * useSpeakerForCli's exclusions: a wired headset plugged in, Bluetooth
     * audio connected or pending, or any Bluetooth output device at all
     * (CommonUtils.getApproximatedAudioRoute counts A2DP, SCO and LE audio).
     */
    private boolean headsetOrBluetoothPresent() {
        final CallAudioState audio = getCallAudioState();
        if (audio == null || audio.getRoute() == CallAudioState.ROUTE_BLUETOOTH
                || (audio.getSupportedRouteMask() & (CallAudioState.ROUTE_WIRED_HEADSET
                        | CallAudioState.ROUTE_BLUETOOTH)) != 0) {
            return true;
        }
        for (AudioDeviceInfo device : getSystemService(AudioManager.class)
                .getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
            switch (device.getType()) {
                case AudioDeviceInfo.TYPE_BLUETOOTH_SCO:
                case AudioDeviceInfo.TYPE_BLUETOOTH_A2DP:
                case AudioDeviceInfo.TYPE_BLE_HEADSET:
                    return true;
                default:
                    break;
            }
        }
        return false;
    }

    /** handleAudioRoutingOnFlipOpenCloseAction's: wired plugged in or Bluetooth audio up. */
    private boolean headsetOrBluetoothInUse() {
        final CallAudioState audio = getCallAudioState();
        if (audio == null) {
            return true; // unknown: leave the route alone
        }
        return (audio.getSupportedRouteMask() & CallAudioState.ROUTE_WIRED_HEADSET) != 0
                || audio.getRoute() == CallAudioState.ROUTE_BLUETOOTH;
    }

    private void showManageCallToast() {
        Toast.makeText(this, R.string.flip_open_to_manage_call, Toast.LENGTH_LONG).show();
    }

    private boolean inEmergencyCall() {
        for (Call call : getCalls()) {
            final Call.Details details = call.getDetails();
            if (details.hasProperty(Call.Details.PROPERTY_EMERGENCY_CALLBACK_MODE)
                    || details.hasProperty(Call.Details.PROPERTY_NETWORK_IDENTIFIED_EMERGENCY_CALL)) {
                return true;
            }
        }
        try {
            return getSystemService(TelecomManager.class).isInEmergencyCall();
        } catch (SecurityException e) {
            Log.w(TAG, "cannot check for an emergency call, assuming one", e);
            return true;
        }
    }

    /**
     * Stock's hasEmergencyRttCall. The RTT property, not isRttActive(): Telecom
     * hands the RTT stream only to the in-call UI, so isRttActive() is always
     * false here.
     */
    private boolean hasEmergencyRttCall() {
        for (Call call : getCalls()) {
            if (call.getDetails().hasProperty(Call.Details.PROPERTY_RTT)) {
                return inEmergencyCall();
            }
        }
        return false;
    }

    /** Stock's areNotificationSuppressed. */
    private boolean notificationsSuppressed() {
        final NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm.getCurrentInterruptionFilter() == NotificationManager.INTERRUPTION_FILTER_ALL) {
            return false;
        }
        // Without an implicit zen rule of our own (we never set one), this is
        // the global policy, the same one stock's Telecom reads.
        final NotificationManager.Policy policy = nm.getNotificationPolicy();
        return policy != null && (policy.suppressedVisualEffects
                & NotificationManager.Policy.SUPPRESSED_EFFECT_NOTIFICATION_LIST) != 0;
    }

    private int currentRoute() {
        final CallAudioState audio = getCallAudioState();
        return audio == null ? -1 : audio.getRoute();
    }

    /**
     * The call the audio follows, in Telecom's order
     * (CallAudioManager.updateForegroundCall): connecting, then active or
     * dialing, then ringing, then held. Conference children and external
     * calls never count (CallAudioManager.shouldIgnoreCallForAudio).
     */
    private Call possiblyHeldForegroundCall() {
        final Call activeOrDialing = activeDialingOrConnectingCall();
        if (activeOrDialing != null) {
            return activeOrDialing;
        }
        Call holding = null;
        for (Call call : getCalls()) {
            if (call.getParent() != null || isExternal(call)) {
                continue;
            }
            if (isRinging(call)) {
                return call;
            }
            if (holding == null && call.getDetails().getState() == Call.STATE_HOLDING) {
                holding = call;
            }
        }
        return holding;
    }

    private Call activeDialingOrConnectingCall() {
        Call activeOrDialing = null;
        for (Call call : getCalls()) {
            if (call.getParent() != null || isExternal(call)) {
                continue;
            }
            switch (call.getDetails().getState()) {
                case Call.STATE_CONNECTING:
                    return call;
                case Call.STATE_ACTIVE:
                case Call.STATE_DIALING:
                    if (activeOrDialing == null) {
                        activeOrDialing = call;
                    }
                    break;
                default:
                    break;
            }
        }
        return activeOrDialing;
    }

    /** CallAudioManager.getForegroundCall: as above, but not a held call. */
    private Call foregroundCall() {
        final Call call = possiblyHeldForegroundCall();
        return call != null && call.getDetails().getState() == Call.STATE_HOLDING ? null : call;
    }

    /** Stock's getFirstCallWithState(RINGING): the foreground call first. */
    private Call firstRingingCall() {
        final Call foreground = foregroundCall();
        if (foreground != null && foreground.getDetails().getState() == Call.STATE_RINGING) {
            return foreground;
        }
        for (Call call : getCalls()) {
            if (call.getParent() == null && !isExternal(call)
                    && call.getDetails().getState() == Call.STATE_RINGING) {
                return call;
            }
        }
        return null;
    }

    private static int settleValue(int state) {
        return state == STATE_OPENED_HALL ? STATE_OPENED : state;
    }

    private static boolean isRinging(Call call) {
        final int state = call.getDetails().getState();
        return state == Call.STATE_RINGING || state == Call.STATE_SIMULATED_RINGING;
    }

    private static boolean isSelfManaged(Call call) {
        return call.getDetails().hasProperty(Call.Details.PROPERTY_SELF_MANAGED);
    }

    private static boolean isExternal(Call call) {
        return call.getDetails().hasProperty(Call.Details.PROPERTY_IS_EXTERNAL_CALL);
    }
}
