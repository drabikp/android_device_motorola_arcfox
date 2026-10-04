/*
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.arcfox.flipcalls;

import android.content.Context;
import android.os.Bundle;
import android.preference.PreferenceDataStore;
import android.preference.PreferenceFragment;

@SuppressWarnings("deprecation") // framework preferences: no 5 MB of SettingsLib
public class FlipCallsFragment extends PreferenceFragment {

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Before inflating, so every switch reads and writes Settings.Global
        // instead of this app's SharedPreferences.
        getPreferenceManager().setPreferenceDataStore(
                new GlobalSettingsStore(getContext().getApplicationContext()));
        addPreferencesFromResource(R.xml.flip_calls_settings);
    }

    /** Ignores the XML default: FlipCallSettings is the single source of it. */
    private static final class GlobalSettingsStore implements PreferenceDataStore {
        private final Context mContext;

        GlobalSettingsStore(Context context) {
            mContext = context;
        }

        @Override
        public boolean getBoolean(String key, boolean defValue) {
            return FlipCallSettings.get(mContext, key);
        }

        @Override
        public void putBoolean(String key, boolean value) {
            FlipCallSettings.set(mContext, key, value);
        }
    }
}
