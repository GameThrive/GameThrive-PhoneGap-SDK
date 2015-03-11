/**
 * Copyright 2014 GameThrive
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.plugin.gcm;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.util.Log;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Iterator;
import java.util.ArrayList;
import java.util.Collection;

import com.gamethrive.GameThrive;
import com.gamethrive.NotificationOpenedHandler;
import com.gamethrive.GameThrive.GetTagsHandler;
import com.gamethrive.GameThrive.IdsAvailableHandler;

public class GameThrivePush extends CordovaPlugin {
	public static final String TAG = "GameThrivePush";

	public static final String INIT = "init";
	public static final String GET_TAGS = "getTags";
	public static final String GET_IDS = "getIds";
	public static final String DELETE_TAGS = "deleteTags";
	public static final String SEND_TAGS = "sendTags";
	public static final String REGISTER_FOR_PUSH_NOTIFICATIONS = "registerForPushNotifications";
	public static final String ENABLE_VIBRATE = "enableVibrate";
	public static final String ENABLE_SOUND = "enableSound";
	
	private static GameThrive gameThrive;
	
	// This is to prevent an issue where if two Javascript calls are made to GameThrive expecting a callback then only one would fire.
	private static void callbackSuccess(CallbackContext callbackContext, JSONObject jsonObject) {
		PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, jsonObject);
		pluginResult.setKeepCallback(true);
		callbackContext.sendPluginResult(pluginResult);
	}
	
	private static void callbackError(CallbackContext callbackContext, String str) {
		PluginResult pluginResult = new PluginResult(PluginResult.Status.ERROR, str);
		pluginResult.setKeepCallback(true);
		callbackContext.sendPluginResult(pluginResult);
	}

	@Override
	public boolean execute(String action, JSONArray data, CallbackContext callbackContext) {
		boolean result = false;

		if (INIT.equals(action)) {
			if (gameThrive != null)
				return false;
			
			try {
				JSONObject jo = data.getJSONObject(0);
				final CallbackContext jsNotificationOpenedCallBack = callbackContext;
				gameThrive = new GameThrive(
					(Activity)this.cordova.getActivity(),
					jo.getString("googleProjectNumber"),
					jo.getString("appId"),
					new NotificationOpenedHandler() {
						@Override
						public void notificationOpened(String message, JSONObject additionalData, boolean isActive) {		
							JSONObject outerObject = new JSONObject();
							try {
								outerObject.put("message", message);
								outerObject.put("additionalData", additionalData);
								outerObject.put("isActive", isActive);
								callbackSuccess(jsNotificationOpenedCallBack, outerObject);
							} catch (Throwable t) {
								t.printStackTrace();
							}
						}
					});
				
				result = true;
			} catch (JSONException e) {
				Log.e(TAG, "execute: Got JSON Exception " + e.getMessage());
				result = false;
			}
		}
		else if (GET_TAGS.equals(action)) {
			final CallbackContext jsTagsAvailableCallBack = callbackContext;
			gameThrive.getTags(new GetTagsHandler() {
				@Override
				public void tagsAvailable(JSONObject tags) {
					callbackSuccess(jsTagsAvailableCallBack, tags);
				}
			});
			result = true;
		}
		else if (GET_IDS.equals(action)) {
			final CallbackContext jsIdsAvailableCallBack = callbackContext;
			gameThrive.idsAvailable(new IdsAvailableHandler() {
				@Override
				public void idsAvailable(String playerId, String registrationId) {
					JSONObject jsonIds = new JSONObject();
					try {
						jsonIds.put("playerId", playerId);
						if (registrationId != null)
							jsonIds.put("pushToken", registrationId);
						else
							jsonIds.put("pushToken", "");
						
						callbackSuccess(jsIdsAvailableCallBack, jsonIds);
					} catch (Throwable t) {
						t.printStackTrace();
					}
				}
			});
			result = true;
		}
		else if (SEND_TAGS.equals(action)) {
			try {
				gameThrive.sendTags(data.getJSONObject(0));
			} catch (Throwable t) {
				t.printStackTrace();
			}
			result = true;
		}
		else if (DELETE_TAGS.equals(action)) {
			try {
				Collection<String> list = new ArrayList<String>();
				for (int i = 0; i < data.length(); i++)
					list.add(data.get(i).toString());
				gameThrive.deleteTags(list);
			} catch (Throwable t) {
				t.printStackTrace();
			}
			result = true;
		}
		else if (REGISTER_FOR_PUSH_NOTIFICATIONS.equals(action)) {
			// Does not apply to Android.
			result = true;
		}
		else if (ENABLE_VIBRATE.equals(action)) {
			if (gameThrive != null) {
				try {
					gameThrive.enableVibrate(data.getBoolean(0));
				} catch (Throwable t) {
					t.printStackTrace();
				}
			}
		}
		else if (ENABLE_SOUND.equals(action)) {
			if (gameThrive != null) {
				try {
					gameThrive.enableSound(data.getBoolean(0));
				} catch (Throwable t) {
					t.printStackTrace();
				}
			}
		}
		else {
			result = false;
			Log.e(TAG, "Invalid action : " + action);
			callbackError(callbackContext, "Invalid action : " + action);
		}

		return result;
	}

	@Override
    public void onPause(boolean multitasking) {
        super.onPause(multitasking);
        if (gameThrive != null)
			gameThrive.onPaused();
    }

    @Override
    public void onResume(boolean multitasking) {
        super.onResume(multitasking);
		if (gameThrive != null)
			gameThrive.onResumed();
    }
}
