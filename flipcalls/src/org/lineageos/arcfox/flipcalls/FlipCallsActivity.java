/*
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.arcfox.flipcalls;

import android.app.Activity;
import android.graphics.Insets;
import android.os.Bundle;
import android.view.View;
import android.view.WindowInsets;

/** Settings > System > Gestures > Flip phone calls. */
public class FlipCallsActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (getActionBar() != null) {
            getActionBar().setDisplayHomeAsUpEnabled(true);
        }

        // Edge-to-edge is enforced from target SDK 35 (and cannot be opted out
        // of from 36): content starts at the top of the window, under the
        // status bar and the action bar, which hid the first switch. The
        // insets ActionBarOverlayLayout hands to the content already include
        // the action bar's height, so applying them is enough.
        final View content = findViewById(android.R.id.content);
        content.setOnApplyWindowInsetsListener((v, insets) -> {
            final Insets bars = insets.getInsets(
                    WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return insets;
        });

        if (savedInstanceState == null) {
            getFragmentManager().beginTransaction()
                    .replace(android.R.id.content, new FlipCallsFragment())
                    .commit();
        }
    }

    @Override
    public boolean onNavigateUp() {
        finish();
        return true;
    }
}
