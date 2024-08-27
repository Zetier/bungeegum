package com.zetier.bungeegum;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.view.Menu;
import java.lang.System;

public class BgActivity extends Activity {
	static final String TAG = "Bungeegum";
	static{
		System.loadLibrary("frida-gadget");
		Log.d(TAG, "Initialized");
	}

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		setContentView(R.layout.activity_bg);
	}

	@Override
	public boolean onCreateOptionsMenu(Menu menu) {
		// Inflate the menu; this adds items to the action bar if it is present.
		getMenuInflater().inflate(R.menu.activity_bg, menu);
		return true;
	}

}
