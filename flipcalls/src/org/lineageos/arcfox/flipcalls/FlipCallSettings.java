/*
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.arcfox.flipcalls;

import android.content.Context;
import android.provider.Settings;

/**
 * The two user switches, kept in Settings.Global like stock keeps its
 * equivalents (MotorolaSettings.Global flip_open_settings / flip_close_settings).
 *
 * <p>Global rather than SharedPreferences because the settings provider is up
 * before the first unlock, when the in-call service may already be needed, and
 * because it makes both switches scriptable: {@code adb shell settings put
 * global arcfox_flip_end_call_on_close 0}. Keys that Settings.java does not
 * declare are exempt from the S+ readability restriction
 * (SettingsProvider.checkReadableAnnotation).
 *
 * <p>Defaults are stock's: answer on open, end the call on close.
 */
final class FlipCallSettings {

    static final String KEY_ANSWER_ON_OPEN = "arcfox_flip_answer_on_open";
    static final String KEY_END_CALL_ON_CLOSE = "arcfox_flip_end_call_on_close";

    private FlipCallSettings() {}

    static boolean answerOnOpen(Context context) {
        return get(context, KEY_ANSWER_ON_OPEN);
    }

    static boolean endCallOnClose(Context context) {
        return get(context, KEY_END_CALL_ON_CLOSE);
    }

    static boolean get(Context context, String key) {
        return Settings.Global.getInt(context.getContentResolver(), key, 1) != 0;
    }

    static void set(Context context, String key, boolean value) {
        Settings.Global.putInt(context.getContentResolver(), key, value ? 1 : 0);
    }
}
