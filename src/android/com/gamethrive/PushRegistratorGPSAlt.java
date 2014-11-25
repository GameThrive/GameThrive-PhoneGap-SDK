/*
 * Copyright 2014 GameThrive
 * Portions Copyright 2012 Google Inc.
 * 
 * This file includes portions from Google Cloud Messaging for Android
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

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.util.Log;

class PushRegistratorGPSAlt implements PushRegistrator {

	private Messenger registrationMessenger;
	private RegisteredHandler registeredHandler;
	private boolean callbackSuccessful = false;
	
	@Override
	public void registerForPush(final Context context, final String googleProjectNumber, RegisteredHandler callback) {
		registeredHandler = callback;
		new Thread(new Runnable() {
    		public void run() {
				Intent regIntent = new Intent("com.google.android.c2dm.intent.REGISTER");
				regIntent.setPackage("com.google.android.gms");
				regIntent.putExtra("app", PendingIntent.getBroadcast(context, 0, new Intent(), 0));
				regIntent.putExtra("sender", googleProjectNumber);
				regIntent.putExtra("google.messenger", getMesseger());
				context.startService(regIntent);
				
				// TODO: Add retrying here;
				
				try {
					Thread.sleep(10000);
				} catch (InterruptedException e) {
					e.printStackTrace();
				}
				if (!callbackSuccessful)
					registeredHandler.complete(null);
    		}
    	}).start();
	}
	
	private Messenger getMesseger() {
		if (registrationMessenger == null) {
			registrationMessenger = new Messenger(new Handler(Looper.getMainLooper())  {
				@Override
				public void handleMessage(Message msg) {
					processGCMRegistartionMessage(msg);
				}});
		}
		
		return registrationMessenger;
	}
	
	private void processGCMRegistartionMessage(Message msg) {
		try {
			String regId = ((Intent)msg.obj).getStringExtra("registration_id");
			callbackSuccessful = true;
			registeredHandler.complete(regId);
		} catch(Throwable t) {
			Log.e(GameThrive.TAG, "Failed to parse GCM Intent: ", t);
		}
	}
}
