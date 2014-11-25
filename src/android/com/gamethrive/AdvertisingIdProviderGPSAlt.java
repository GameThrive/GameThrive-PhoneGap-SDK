package com.gamethrive;

import java.io.IOException;
import java.util.concurrent.LinkedBlockingQueue;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.pm.PackageManager;
import android.content.pm.PackageManager.NameNotFoundException;
import android.os.IBinder;
import android.os.IInterface;
import android.os.Parcel;
import android.os.RemoteException;
import android.util.Log;

public final class AdvertisingIdProviderGPSAlt implements AdvertisingIdentifierProvider {

	private static final class AdInfo {
		private final String advertisingId;
		private final boolean limitAdTrackingEnabled;

		AdInfo(String advertisingId, boolean limitAdTrackingEnabled) {
			this.advertisingId = advertisingId;
			this.limitAdTrackingEnabled = limitAdTrackingEnabled;
		}

		public String getId() {
			return this.advertisingId;
		}

		public boolean isLimitAdTrackingEnabled() {
			return this.limitAdTrackingEnabled;
		}
	}

	private static AdInfo getAdvertisingIdInfo(Context context) throws IOException, NameNotFoundException, RemoteException, InterruptedException {
		PackageManager pm = context.getPackageManager();
		pm.getPackageInfo("com.android.vending", 0);
		
		AdvertisingConnection connection = new AdvertisingConnection();
		Intent intent = new Intent("com.google.android.gms.ads.identifier.service.START");
		intent.setPackage("com.google.android.gms");
		if (context.bindService(intent, connection, Context.BIND_AUTO_CREATE)) {
			try {
				AdvertisingInterface adInterface = new AdvertisingInterface(connection.getBinder());
				AdInfo adInfo = new AdInfo(adInterface.getId(), adInterface.isLimitAdTrackingEnabled(true));
				return adInfo;
			} finally {
				context.unbindService(connection);
			}
		}
		
		throw new IOException("Google Play connection failed");
	}

	private static final class AdvertisingConnection implements ServiceConnection {
		boolean retrieved = false;
		private final LinkedBlockingQueue<IBinder> queue = new LinkedBlockingQueue<IBinder>(1);

		@Override
		public void onServiceConnected(ComponentName name, IBinder service) {
			try {
				this.queue.put(service);
			} catch (InterruptedException localInterruptedException) {
			}
		}

		@Override
		public void onServiceDisconnected(ComponentName name) {
		}

		public IBinder getBinder() throws InterruptedException {
			if (this.retrieved)
				throw new IllegalStateException();
			this.retrieved = true;
			return this.queue.take();
		}
	}

	private static final class AdvertisingInterface implements IInterface {
		private IBinder binder;

		public AdvertisingInterface(IBinder pBinder) {
			binder = pBinder;
		}

		@Override
		public IBinder asBinder() {
			return binder;
		}

		public String getId() throws RemoteException {
			Parcel data = Parcel.obtain();
			Parcel reply = Parcel.obtain();
			String id;
			try {
				data.writeInterfaceToken("com.google.android.gms.ads.identifier.internal.IAdvertisingIdService");
				binder.transact(1, data, reply, 0);
				reply.readException();
				id = reply.readString();
			} finally {
				reply.recycle();
				data.recycle();
			}
			return id;
		}

		public boolean isLimitAdTrackingEnabled(boolean paramBoolean) throws RemoteException {
			Parcel data = Parcel.obtain();
			Parcel reply = Parcel.obtain();
			boolean limitAdTracking;
			try {
				data.writeInterfaceToken("com.google.android.gms.ads.identifier.internal.IAdvertisingIdService");
				data.writeInt(paramBoolean ? 1 : 0);
				binder.transact(2, data, reply, 0);
				reply.readException();
				limitAdTracking = 0 != reply.readInt();
			} finally {
				reply.recycle();
				data.recycle();
			}
			return limitAdTracking;
		}
	}

	@Override
	public String getIdentifier(Context appContext) {
		try {
			AdInfo adInfo = getAdvertisingIdInfo(appContext);
			final String id = adInfo.getId();
			final boolean isLAT = adInfo.isLimitAdTrackingEnabled();
			if (isLAT)
				return "OptedOut"; // Google restricts usage of the id to "build profiles" if the user checks opt out so we can't collect.
			return id;
		}
		catch (Throwable t) {
			Log.w(GameThrive.TAG, "Error getting Google Ad Id: ", t);
		}
		
		return null;
	}
}