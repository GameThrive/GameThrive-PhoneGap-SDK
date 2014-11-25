package com.gamethrive;

import android.content.Context;
import android.net.wifi.WifiManager;
import android.provider.Settings;
import android.telephony.TelephonyManager;

public class AdvertisingIdProviderFallback implements AdvertisingIdentifierProvider {

	// See links on alternative unique IDs for players
	// http://technet.weblineindia.com/mobile/getting-unique-device-id-of-an-android-smartphone/
	// http://stackoverflow.com/questions/2785485/is-there-a-unique-android-device-id
	
	@Override
	public String getIdentifier(Context appContext) {
		String id;

		id = getPhoneId(appContext);
		if (id != null)
			return id;
		
		id = getAndroidId(appContext);
		if (id != null)
			return id;
		
		return getWifiMac(appContext);
	}

	// Requires android.permission.READ_PHONE_STATE permission
	private String getPhoneId(Context appContext) {
		try {
			return ((TelephonyManager) appContext.getSystemService(Context.TELEPHONY_SERVICE)).getDeviceId();
		}
		catch (RuntimeException e) {}
		return null;
	}
	
	private String getAndroidId(Context appContext) {
		try {
			final String androidId = Settings.Secure.getString(appContext.getContentResolver(), Settings.Secure.ANDROID_ID);
			// see http://code.google.com/p/android/issues/detail?id=10603 for info on this 'dup' id.
			if (androidId != "9774d56d682e549c")
				return androidId;
		}
		catch (RuntimeException e) {}

		return null;
	}
	
	// Requires android.permission.ACCESS_WIFI_STATE permission
	private String getWifiMac(Context appContext) {
		try {
			return ((WifiManager)appContext.getSystemService(Context.WIFI_SERVICE)).getConnectionInfo().getMacAddress();
		}
		catch (RuntimeException e) {}
		
		return null;
	}
}