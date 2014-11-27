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

// register is deprecated, must use init instead.
GameThrive.prototype.register = function(successCallback, errorCallback, options) {
    console.log("GameThrive.register is deprecated, must use init instead.");
};

// unregister is Deprecated. Please use a tag to flag a user as no longer registered.
GameThrive.prototype.unregister = function(successCallback, errorCallback, options) {
	console.log("GameThrive.unregister is deprecated and no longer does anything. Please use a tag to flag a user as no longer registered.");
};

// Only applies to iOS(does nothing on Android as it always silently registers)
// Call only if you passed false to autoRegister
GameThrive.prototype.registerForPushNotifications = function() {
    cordova.exec(function(){}, function(){}, "GameThrivePush", "registerForPushNotifications", []);
}

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