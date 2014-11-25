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

package com.gamethrive;

import org.json.JSONObject;

public interface NotificationOpenedHandler {
	/**
	 * Callback to implement in your app to handle when a notification is opened from the Android status bar or
	 * a new one comes in while the app is running.
	 *
	 * @param message        The message string the user seen/should see in the Android status bar.
	 * @param additionalData The additionalData key value pair section you entered in on gamethrive.com.
	 * @param isActive       Was the app in the foreground when the notification was received. 
	 */
	void notificationOpened(String message, JSONObject additionalData, boolean isActive);
}
