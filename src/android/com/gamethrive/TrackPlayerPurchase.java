package com.gamethrive;

import java.lang.reflect.Method;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.apache.http.Header;

import com.gamethrive.GameThrive.IdsAvailableHandler;
import com.loopj.android.http.JsonHttpResponseHandler;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.IBinder;
import android.util.Log;

class TrackPlayerPurchase {

	static private int iapEnabled = -99;
	private ServiceConnection mServiceConn;
	private static Class<?> IInAppBillingServiceClass;
	private Object mIInAppBillingService;
	private Method getPurchasesMethod, getSkuDetailsMethod;
	private Activity appContext;

	private ArrayList<String> purchaseTokens;
	private SharedPreferences.Editor prefsEditor;

	private GameThrive gameThrive;
	
	// Any new purchases found count as pre-existing.
	// The constructor sets it to false if we already saved any purchases or already found out there isn't any.
	private boolean newAsExisting = true;
	private boolean isWaitingForPurchasesRequest = false;
	
	TrackPlayerPurchase(Activity activity, GameThrive inGameThrive) {
		appContext = activity;
		gameThrive = inGameThrive;

		SharedPreferences prefs = appContext.getSharedPreferences("GTPlayerPurchases", Context.MODE_PRIVATE);
		prefsEditor = prefs.edit();

		purchaseTokens = new ArrayList<String>();
		try {
			JSONArray jsonPurchaseTokens = new JSONArray(prefs.getString("purchaseTokens", "[]"));
			for(int i = 0; i < jsonPurchaseTokens.length(); i++)
				purchaseTokens.add(jsonPurchaseTokens.get(i).toString());
			newAsExisting = (jsonPurchaseTokens.length() == 0);
			if (newAsExisting)
				newAsExisting = prefs.getBoolean("ExistingPurchases", true);
		} catch (JSONException e) {
			e.printStackTrace();
		}
		
		trackIAP();
	}

	static boolean CanTrack(Activity activity) {
		if (iapEnabled == -99)
			iapEnabled = activity.checkCallingOrSelfPermission("com.android.vending.BILLING");
		try {
			if (iapEnabled == PackageManager.PERMISSION_GRANTED)
				IInAppBillingServiceClass = Class.forName("com.android.vending.billing.IInAppBillingService");
		} catch (Throwable t) {
			iapEnabled = 0;
			return false;
		}

		return (iapEnabled == PackageManager.PERMISSION_GRANTED);
	}

	void trackIAP() {
		if (mServiceConn == null) {
			mServiceConn = new ServiceConnection() {
				@Override
				public void onServiceDisconnected(ComponentName name) {
					iapEnabled = -99;
					mIInAppBillingService = null;
				}

				@Override
				public void onServiceConnected(ComponentName name, IBinder service) {
					try {
						Class<?> stubClass = Class.forName("com.android.vending.billing.IInAppBillingService$Stub");
						Method asInterfaceMethod = stubClass.getMethod("asInterface", android.os.IBinder.class);
						mIInAppBillingService = asInterfaceMethod.invoke(null, service);
						
						QueryBoughtItems();
					}
					catch (Throwable t) {
						t.printStackTrace();
					}
				}
			};

			Intent serviceIntent = new Intent("com.android.vending.billing.InAppBillingService.BIND");
			serviceIntent.setPackage("com.android.vending");
			appContext.bindService(serviceIntent, mServiceConn, Context.BIND_AUTO_CREATE);
		}
		else if (mIInAppBillingService != null)
			QueryBoughtItems();
	}

	private void QueryBoughtItems() {
		if (isWaitingForPurchasesRequest)
			return;
		
		new Thread(new Runnable() {
			public void run() {
				isWaitingForPurchasesRequest = true;
				try {					
					if (getPurchasesMethod == null)
						getPurchasesMethod = IInAppBillingServiceClass.getMethod("getPurchases", int.class, String.class, String.class, String.class);
		
					Bundle ownedItems = (Bundle)getPurchasesMethod.invoke(mIInAppBillingService, 3, appContext.getPackageName(), "inapp", null);
					if (ownedItems.getInt("RESPONSE_CODE") == 0) {
						ArrayList<String> skusToAdd = new ArrayList<String>();
						ArrayList<String> newPurchaseTokens = new ArrayList<String>();
						
						ArrayList<String> ownedSkus = ownedItems.getStringArrayList("INAPP_PURCHASE_ITEM_LIST");
						ArrayList<String> purchaseDataList = ownedItems.getStringArrayList("INAPP_PURCHASE_DATA_LIST");
		
						for (int i = 0; i < purchaseDataList.size(); i++) {
							String purchaseData = purchaseDataList.get(i);
							String sku = ownedSkus.get(i);
							JSONObject itemPurchased = new JSONObject(purchaseData);
							String purchaseToken = itemPurchased.getString("purchaseToken");
		
							if (!purchaseTokens.contains(purchaseToken) && !newPurchaseTokens.contains(purchaseToken)) {
								newPurchaseTokens.add(purchaseToken);
								skusToAdd.add(sku);
							}
						}
						
						if (skusToAdd.size() > 0)
							sendPurchases(skusToAdd, newPurchaseTokens);
						else if (purchaseDataList.size() == 0) {
							newAsExisting = false;
							prefsEditor.putBoolean("ExistingPurchases", false);
							prefsEditor.commit();
						}
		
						// TODO: Handle very large list. Test for continuationToken != null then call getPurchases again
					}
				} catch (Throwable e) {
					e.printStackTrace();
				}
				isWaitingForPurchasesRequest = false;
			}
        }).start();
	}

	private void sendPurchases(final ArrayList<String> skusToAdd, final ArrayList<String> newPurchaseTokens) {
		try {	
			if (getSkuDetailsMethod == null)
				getSkuDetailsMethod = IInAppBillingServiceClass.getMethod("getSkuDetails", int.class, String.class, String.class, Bundle.class);
			
			Bundle querySkus = new Bundle();
			querySkus.putStringArrayList("ITEM_ID_LIST", skusToAdd);
			Bundle skuDetails = (Bundle)getSkuDetailsMethod.invoke(mIInAppBillingService, 3, appContext.getPackageName(), "inapp", querySkus);
			
			int response = skuDetails.getInt("RESPONSE_CODE");
			if (response == 0) {
				ArrayList<String> responseList = skuDetails.getStringArrayList("DETAILS_LIST");
				Map<String, JSONObject> currentSkus = new HashMap<String, JSONObject>();
				JSONObject jsonItem;
				for (String thisResponse : responseList) {
					JSONObject object = new JSONObject(thisResponse);
					String sku = object.getString("productId");
					BigDecimal price = new BigDecimal(object.getString("price_amount_micros"));
					price = price.divide(new BigDecimal(1000000));

					jsonItem = new JSONObject();
					jsonItem.put("sku", sku);
					jsonItem.put("iso", object.getString("price_currency_code"));
					jsonItem.put("amount", price.toString());
					currentSkus.put(sku, jsonItem);
				}
				
				JSONArray purchasesToReport = new JSONArray();
				for(String sku : skusToAdd) {
					if (!currentSkus.containsKey(sku))
						continue;
					purchasesToReport.put(currentSkus.get(sku));
				}

				// New purchases to report.
				// Wait until we have a playerID then send purchases to server. If successful then mark them as tracked.
				if (purchasesToReport.length() > 0) {
					final JSONArray finalPurchasesToReport = purchasesToReport;
					gameThrive.idsAvailable(new IdsAvailableHandler() {
						public void idsAvailable(String playerId, String registrationId) {
							gameThrive.sendPurchases(finalPurchasesToReport, newAsExisting, new JsonHttpResponseHandler() {
				    			public void onFailure(int statusCode, Header[] headers, Throwable throwable, JSONObject errorResponse) {
				    				Log.i(GameThrive.TAG, "JSON sendPurchases Failed");
				    				throwable.printStackTrace();
				    				isWaitingForPurchasesRequest = false;
				    			}
								public void onSuccess(int statusCode, Header[] headers, JSONObject response) {
									purchaseTokens.addAll(newPurchaseTokens);
									prefsEditor.putString("purchaseTokens", purchaseTokens.toString());
									prefsEditor.remove("ExistingPurchases");
									prefsEditor.commit();
									newAsExisting = false;
									isWaitingForPurchasesRequest = false;
								}
				    		});
						}
					});

				}
			}
		}
		catch(Throwable t) {
			t.printStackTrace();
		}
	}
}