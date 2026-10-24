package com.ambi.lifekeeper

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class SystemReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_DATE_CHANGED, Intent.ACTION_MY_PACKAGE_REPLACED)) return
        val pending = goAsync()
        val handler = Handler(Looper.getMainLooper())
        handler.post {
            var engine: FlutterEngine? = null
            var finished = false
            fun finish() {
                if (!finished) {
                    finished = true
                    engine?.destroy()
                    pending.finish()
                }
            }
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(context.applicationContext)
                loader.ensureInitializationComplete(context.applicationContext, null)
                engine = FlutterEngine(context.applicationContext)
                val channel = MethodChannel(engine!!.dartExecutor.binaryMessenger, "lifekeeper/system")
                channel.setMethodCallHandler { call, result ->
                    if (call.method == "done") { result.success(null); handler.post { finish() } } else result.notImplemented()
                }
                engine!!.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "systemReconcile"))
                handler.postDelayed({ finish() }, 9000)
            } catch (_: Exception) { finish() }
        }
    }
}
