/**
 * Copyright 2014 GameThrive
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

var GameThrive = function() {
};


// You must call init before any other GameThrive function.
// options is a JSON object that includes:
//  Android - googleProjectNumber: is required.
//  iOS - autoRegister: Set as false to delay the iOS push notification permisions system prompt.
//                      Make sure to call registerForPushNotifications sometime later.
GameThrive.prototype.init = function(appId, options, didReceiveRemoteNotificationCallBack) {
    if (didReceiveRemoteNotificationCallBack == null)
        didReceiveRemoteNotificationCallBack = function() {};
    
    options.appId = appId;
    cordova.exec(didReceiveRemoteNotificationCallBack, function(){}, "GameThrivePush", "init", [options]);
};

GameThrive.prototype.getTags = function(tagsReceivedCallBack) {
    cordova.exec(tagsReceivedCallBack, function(){}, "GameThrivePush", "getTags", []);
};

GameThrive.prototype.getIds = function(IdsReceivedCallBack) {
    cordova.exec(IdsReceivedCallBack, function(){}, "GameThrivePush", "getIds", []);
};

GameThrive.prototype.sendTag = function(key, value) {
    jsonKeyValue = {};
    jsonKeyValue[key] = value;
    cordova.exec(function(){}, function(){}, "GameThrivePush", "sendTags", [jsonKeyValue]);
};

GameThrive.prototype.sendTags = function(tags) {
    cordova.exec(function(){}, function(){}, "GameThrivePush", "sendTags", [tags]);
};

GameThrive.prototype.deleteTag = function(key) {
    cordova.exec(function(){}, function(){}, "GameThrivePush", "deleteTags", [key]);
};

GameThrive.prototype.deleteTags = function(keys) {
    cordova.exec(function(){}, function(){}, "GameThrivePush", "deleteTags", keys);
};

// Only applies to iOS(does nothing on Android as it always silently registers)
// Call only if you passed false to autoRegister
GameThrive.prototype.registerForPushNotifications = function() {
    cordova.exec(function(){}, function(){}, "GameThrivePush", "registerForPushNotifications", []);
};

// Only applies to Android, vibrate is on by default but can be disabled by passing in false.
GameThrive.prototype.enableVibrate = function(enable) {
    cordova.exec(function(){}, function(){}, "GameThrivePush", "enableVibrate", [enable]);
};

// Only applies to Android, sound is on by default but can be disabled by passing in false.
GameThrive.prototype.enableSound = function(enable) {
    cordova.exec(function(){}, function(){}, "GameThrivePush", "enableSound", [enable]);
};

//-------------------------------------------------------------------

if(!window.plugins) {
    window.plugins = {};
}
if (!window.plugins.GameThrive) {
    window.plugins.GameThrive = new GameThrive();
}

if (typeof module != 'undefined' && module.exports) {
  module.exports = GameThrive;
}