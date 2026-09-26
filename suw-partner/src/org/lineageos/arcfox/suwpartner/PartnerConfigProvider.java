/*
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */
package org.lineageos.arcfox.suwpartner;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;

/**
 * Answers the setupcompat PartnerConfigHelper "call" methods so the setup-style
 * screens of GApps-less builds (the EuiccGoogle eSIM wizard) follow the system
 * DayNight theme. Every method the library asks about is answered with the
 * boolean stored under the method name; unknown methods return an empty Bundle,
 * which the library treats as "not configured" and falls back to its defaults.
 */
public class PartnerConfigProvider extends ContentProvider {
    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        Bundle result = new Bundle();
        if (method == null) {
            return result;
        }
        switch (method) {
            case "isSuwDayNightEnabled":      // follow the system dark theme
            case "isDynamicColorEnabled":     // Material You accent, like LineageOS itself
                result.putBoolean(method, true);
                break;
            case "getOverlayConfig":          // no partner resource overrides
            default:
                break;
        }
        return result;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs,
            String sortOrder) {
        return null;
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        return 0;
    }
}
