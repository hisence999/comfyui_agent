package com.comfyui.mobile.comfy_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.comfyui.mobile/mediastore"
    private lateinit var mediaStoreHelper: MediaStoreHelper

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mediaStoreHelper = MediaStoreHelper(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "deleteImageByFilename" -> {
                    val filename = call.argument<String>("filename")
                    if (filename != null) {
                        mediaStoreHelper.deleteImageByFilename(filename, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "filename is required", null)
                    }
                }
                "deleteImageByPath" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        mediaStoreHelper.deleteImageByPath(path, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "path is required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
