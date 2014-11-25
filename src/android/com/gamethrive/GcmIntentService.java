/**
 * Copyright 2014 GameThrive
 * Portions Copyright 2013 Google Inc.
 * 
 * This file includes portions from the Google GcmClient demo project
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

package com.gamethrive;

import java.util.Random;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.R.drawable;
import android.app.IntentService;
import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.support.v4.app.NotificationCompat;

/**
 * This {@code IntentService} does the actual handling of the GCM message.
 * {@code GcmBroadcastReceiver} (a {@code WakefulBroadcastReceiver}) holds a
 * partial wake lock for this service while the service does its work. When the
 * service is finished, it calls {@code completeWakefulIntent()} to release the
 * wake lock.
 */
public class GcmIntentService extends IntentService {
    private static final String DEFAULT_ACTION = "__DEFAULT__";
    
    private static final String GCM_RECIEVE = "com.google.android.c2dm.intent.RECEIVE";
    private static final String GCM_TYPE = "gcm";
    
    private NotificationManager mNotificationManager;

    public GcmIntentService() {
        super("GcmIntentService");
    }
    
    public static final String TAG = "GameThrive";
    
    private static boolean isGcmMessage(Intent intent) {
    	if (GCM_RECIEVE.equals(intent.getAction())) {
    		String messageType = intent.getStringExtra("message_type");
    		return (messageType == null || GCM_TYPE.equals(messageType));
    	}
    	return false;
    }

    @Override
    protected void onHandleIntent(Intent intent) {
        Bundle extras = intent.getExtras();
        
    	if (isGcmMessage(intent) && !extras.isEmpty()) {
        	PrepareBundle(extras);
        	
        	// If GameThrive has been initialized and the app is in focus skip the notification creation and handle everything like it was opened. 
    		if (GameThrive.instance != null && GameThrive.instance.isForeground()) {
            	final Bundle finalExtras = extras;
    			// This IntentService is meant to be short lived. Make a new thread to do our GameThrive work on.
    			new Thread(new Runnable() {
    				public void run() {
    					GameThrive.instance.handleNotificationOpened(finalExtras);
    				}
    			}).start();
    		 }
    		 else // Create notification from the GCM message.
                 sendNotification(extras);
         }
        
        // Release the wake lock provided by the WakefulBroadcastReceiver.
        GcmBroadcastReceiver.completeWakefulIntent(intent);
    }
    
    // Format our short keys into more readable ones.
    private void PrepareBundle(Bundle gcmBundle) {
    	if (gcmBundle.containsKey("o")) {
			try {
		    	JSONObject customJSON = new JSONObject(gcmBundle.getString("custom"));
		    	JSONObject additionalDataJSON;
		    	
		    	if (customJSON.has("a"))
					additionalDataJSON = customJSON.getJSONObject("a");
		   		else
		   			additionalDataJSON = new JSONObject();
		    	
		    	JSONArray buttons = new JSONArray(gcmBundle.getString("o"));
		    	gcmBundle.remove("o");
		    	for(int i = 0; i < buttons.length(); i++) {
		    		JSONObject button = buttons.getJSONObject(i);
		    		
		    		String buttonText = button.getString("n");
		    		button.remove("n");
		    		String buttonId;
		    		if (button.has("i")){
		    			buttonId = button.getString("i");
		    			button.remove("i");
		    		}
		    		else
		    			buttonId = buttonText;
		    		
		    		button.put("id", buttonId);
		    		button.put("text", buttonText);
		    	}
		    	
				additionalDataJSON.put("actionButtons", buttons);
				additionalDataJSON.put("actionSelected", DEFAULT_ACTION);
				if (!customJSON.has("a"))
					customJSON.put("a", additionalDataJSON);
		    	
		    	gcmBundle.putString("custom", customJSON.toString());
			} catch (JSONException e) {
				e.printStackTrace();
			}
    	}
    }
    
    private Intent getNewBaseIntent() {
    	return new Intent(this, NotificationOpenedActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    }
    
    // Put the message into a notification and post it.
    private void sendNotification(Bundle gcmBundle) {
    	Random random = new Random();
    	
    	int intentId = random.nextInt();
    	int notificationId = random.nextInt();
    	
        mNotificationManager = (NotificationManager) this.getSystemService(Context.NOTIFICATION_SERVICE);
        
        PendingIntent contentIntent = PendingIntent.getActivity(this, intentId, getNewBaseIntent().putExtra("data", gcmBundle), PendingIntent.FLAG_UPDATE_CURRENT);
        
        int notificationIcon = getResources().getIdentifier("gamethrive_statusbar_icon_default", "drawable", getPackageName());
        
        if (notificationIcon == 0)
        	notificationIcon = getResources().getIdentifier("corona_statusbar_icon_default", "drawable", getPackageName());
        
        if (notificationIcon == 0) {
	        notificationIcon = this.getApplicationInfo().icon;
	        if (notificationIcon == 0) // Catches case where icon isn't set in the AndroidManifest.xml
	        	notificationIcon = drawable.sym_def_app_icon;
        }
        
        CharSequence title = gcmBundle.getString("title");
        if (title == null)
        	title = getPackageManager().getApplicationLabel(getApplicationInfo());
        
        int notificationDefaults = Notification.DEFAULT_LIGHTS | Notification.DEFAULT_VIBRATE;
        
        NotificationCompat.Builder mBuilder = new NotificationCompat.Builder(this)
	        .setAutoCancel(true)
	        .setSmallIcon(notificationIcon) // Small Icon required or notification doesn't display
	        //.setLargeIcon(BitmapFactory.decodeResource(getResources(), getApplicationInfo().icon))
	        .setContentTitle(title)
	        .setStyle(new NotificationCompat.BigTextStyle().bigText(gcmBundle.getString("alert")))
	        .setTicker(gcmBundle.getString("alert"))
	        .setContentText(gcmBundle.getString("alert"));
        
        if (gcmBundle.getString("sound") != null) {
        	int soundId = getResources().getIdentifier(gcmBundle.getString("sound"), "raw", getPackageName());
        	if (soundId != 0)
        		mBuilder.setSound(Uri.parse(ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + getPackageName() + "/" + soundId));
        	else
            	notificationDefaults |= Notification.DEFAULT_SOUND;
        }
        else
        	notificationDefaults |= Notification.DEFAULT_SOUND;
        
        mBuilder.setDefaults(notificationDefaults);
        mBuilder.setContentIntent(contentIntent);
		
		try {
	        JSONObject customJson = new JSONObject(gcmBundle.getString("custom"));
	        
	        if (customJson.has("a")) {
	        	JSONObject additionalDataJSON = customJson.getJSONObject("a");
	        	if (additionalDataJSON.has("actionButtons")) {
	        		
	            	JSONArray buttons = additionalDataJSON.getJSONArray("actionButtons");
    				
            		for(int i = 0; i < buttons.length(); i++) {
            			JSONObject button = buttons.getJSONObject(i);
            			additionalDataJSON.put("actionSelected", button.getString("id"));
            			
            			Bundle bundle = new Bundle();
            			bundle.putString("custom", customJson.toString());
            			bundle.putString("alert", gcmBundle.getString("alert"));
            			
            			Intent buttonIntent = getNewBaseIntent();
            			buttonIntent.setAction("" + i); // Required to keep each action button from replacing extras of each other
            			buttonIntent.putExtra("notificationId", notificationId);
            			buttonIntent.putExtra("data", bundle);
            			PendingIntent buttonPIntent = PendingIntent.getActivity(this, notificationId, buttonIntent, PendingIntent.FLAG_UPDATE_CURRENT);
            			mBuilder.addAction(0, button.getString("text"), buttonPIntent);
            		}
	        	}
	        }
		} catch (JSONException e) {
			e.printStackTrace();
		}
		
        mNotificationManager.notify(notificationId, mBuilder.build());
    }
}