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

import java.io.UnsupportedEncodingException;

import org.apache.http.entity.StringEntity;
import org.json.JSONObject;

import android.content.Context;

import com.loopj.android.http.*;


// We use new Threads for async calls instead of loopj's AsyncHttpClient for 2 reasons:
// 1. To make sure our callbacks finish in cases where these methods might be called from a short lived thread.
// 2. If there isn't a looper on the current thread we can't use loopj's built in async implementation without calling
//    Looper.prepare() which can have unexpected results on the current thread.

class GameThriveRestClient {
  private static final String BASE_URL = "https://gamethrive.com/api/v1/";
  private static final int TIMEOUT = 20000;
  
  private static SyncHttpClient clientSync = new SyncHttpClient();
  
  static {
	  // setTimeout method = socket timeout
	  // setMaxRetriesAndTimeout = sleep between retries
	  clientSync.setTimeout(TIMEOUT);
	  clientSync.setMaxRetriesAndTimeout(3, TIMEOUT);
  }
  
  static void put(final Context context, final String url, JSONObject jsonBody, final ResponseHandlerInterface responseHandler) throws UnsupportedEncodingException {
	  final StringEntity entity = new StringEntity(jsonBody.toString());
	  
	  new Thread(new Runnable() {
	      public void run() {
	    	  clientSync.put(context, BASE_URL + url, entity, "application/json", responseHandler);
	      }
	  }).start();
  }

  static void post(final Context context, final String url, JSONObject jsonBody, final ResponseHandlerInterface responseHandler) throws UnsupportedEncodingException {
	  final StringEntity entity = new StringEntity(jsonBody.toString());
	  
	  new Thread(new Runnable() {
	      public void run() {
	    	  clientSync.post(context, BASE_URL + url, entity, "application/json", responseHandler);
	      }
	  }).start();
  }
  
  static void get(final Context context, final String url, final ResponseHandlerInterface responseHandler) {
	  new Thread(new Runnable() {
	      public void run() {
	    	  clientSync.get(context, BASE_URL + url, responseHandler);
	   		}
	  }).start();
  }
  
  static void putSync(Context context, String url, JSONObject jsonBody, ResponseHandlerInterface responseHandler) throws UnsupportedEncodingException {
	  StringEntity entity = new StringEntity(jsonBody.toString());
	  clientSync.put(context, BASE_URL + url, entity, "application/json", responseHandler);
  }

  static void postSync(Context context, String url, JSONObject jsonBody, ResponseHandlerInterface responseHandler) throws UnsupportedEncodingException {
	  StringEntity entity = new StringEntity(jsonBody.toString());
	  clientSync.post(context, BASE_URL + url, entity, "application/json", responseHandler);
  }

}