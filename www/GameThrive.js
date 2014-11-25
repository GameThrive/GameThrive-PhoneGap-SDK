var GameThrive = function() {
};


// Call init before any other GameThrive function.
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


// Call this to set the application icon badge
GameThrive.prototype.setApplicationIconBadgeNumber = function(successCallback, errorCallback, badge) {
    if (errorCallback == null) { errorCallback = function() {}}

    if (typeof errorCallback != "function")  {
        console.log("GameThrive.setApplicationIconBadgeNumber failure: failure parameter not a function");
        return
    }

    if (typeof successCallback != "function") {
        console.log("GameThrive.setApplicationIconBadgeNumber failure: success callback parameter must be a function");
        return
    }

    cordova.exec(successCallback, errorCallback, "GameThrivePush", "setApplicationIconBadgeNumber", [{badge: badge}]);
};

// Not active as WP8 is not support yet.
GameThrive.prototype.showToastNotification = function (successCallback, errorCallback, options) {
	console.log("GameThrive.showToastNotification Not active as WP8 is not support yet.");
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