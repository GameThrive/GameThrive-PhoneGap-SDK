
var GameThrive = function() {
};


	// Call this to register for push notifications. Content of [options] depends on whether we are working with APNS (iOS) or GCM (Android)
	GameThrive.prototype.register = function(successCallback, errorCallback, options) {
    	if (errorCallback == null) { errorCallback = function() {}}

		if (typeof errorCallback != "function")  {
			console.log("GameThrive.register failure: failure parameter not a function");
			return;
		}

		if (typeof successCallback != "function") {
			console.log("GameThrive.register failure: success callback parameter must be a function");
			return;
		}

		cordova.exec(successCallback, errorCallback, "PushPlugin", "register", [options]);
	};

    // Call this to unregister for push notifications
    GameThrive.prototype.unregister = function(successCallback, errorCallback) {
		if (errorCallback == null) { errorCallback = function() {}}

		if (typeof errorCallback != "function")  {
			console.log("GameThrive.unregister failure: failure parameter not a function");
			return;
		}

		if (typeof successCallback != "function") {
			console.log("GameThrive.unregister failure: success callback parameter must be a function");
			return;
		}

		cordova.exec(successCallback, errorCallback, "PushPlugin", "unregister", []);
    };
 
 
    // Call this to set the application icon badge
    GameThrive.prototype.setApplicationIconBadgeNumber = function(successCallback, badge) {
		if (errorCallback == null) { errorCallback = function() {}}

		if (typeof errorCallback != "function")  {
			console.log("GameThrive.setApplicationIconBadgeNumber failure: failure parameter not a function");
			return;
		}

		if (typeof successCallback != "function") {
			console.log("GameThrive.setApplicationIconBadgeNumber failure: success callback parameter must be a function");
			return;
		}

		cordova.exec(successCallback, successCallback, "PushPlugin", "setApplicationIconBadgeNumber", [{badge: badge}]);
    };

//-------------------------------------------------------------------

if(!window.plugins) {
	window.plugins = {};
}
if (!window.plugins.GameThrive) {
	window.plugins.GameThrive = new GameThrive();
}
