package com.gabiuz.sync_it

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.gabiuz.sync_it/incoming_files"
        private const val EVENT_CHANNEL = "com.gabiuz.sync_it/incoming_files_events"
        private val SUPPORTED_EXTENSIONS = setOf("gpx", "tcx", "fit")
    }

    private var initialBatch: Map<String, Any>? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialBatch = extractBatchFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val batch = extractBatchFromIntent(intent) ?: return
        if (eventSink != null) {
            eventSink?.success(batch)
        } else {
            initialBatch = batch
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialIncomingSources") {
                val payload = initialBatch
                initialBatch = null
                result.success(payload)
            } else {
                result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun extractBatchFromIntent(intent: Intent?): Map<String, Any>? {
        if (intent == null) return null
        val uris = collectUris(intent)
        if (uris.isEmpty()) return null

        val files = mutableListOf<Map<String, Any>>()
        val errors = mutableListOf<String>()

        for (uri in uris) {
            val fileName = resolveFileName(uri)
            val ext = fileName.substringAfterLast('.', "").lowercase()
            if (ext.isNotEmpty() && ext !in SUPPORTED_EXTENSIONS) {
                errors.add(
                    "Unsupported file type \"$fileName\". Sync-It only supports .gpx, .tcx, and .fit files."
                )
                continue
            }

            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes == null) {
                    errors.add("Unable to read shared file \"$fileName\".")
                } else {
                    files.add(
                        mapOf(
                            "fileName" to fileName,
                            "bytes" to bytes
                        )
                    )
                }
            } catch (_: Exception) {
                errors.add("Unable to read shared file \"$fileName\".")
            }
        }

        if (files.isEmpty() && errors.isEmpty()) return null
        return mapOf(
            "files" to files,
            "errors" to errors
        )
    }

    private fun collectUris(intent: Intent): List<Uri> {
        val uris = linkedSetOf<Uri>()
        when (intent.action) {
            Intent.ACTION_VIEW -> {
                intent.data?.let { uris.add(it) }
            }
            Intent.ACTION_SEND -> {
                val streamUri = getParcelableUri(intent, Intent.EXTRA_STREAM)
                if (streamUri != null) uris.add(streamUri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val streamUris = getParcelableUriList(intent, Intent.EXTRA_STREAM)
                uris.addAll(streamUris)
            }
        }

        val clipData = intent.clipData
        if (uris.isEmpty() && clipData != null) {
            for (i in 0 until clipData.itemCount) {
                clipData.getItemAt(i).uri?.let { uris.add(it) }
            }
        }
        return uris.toList()
    }

    private fun getParcelableUri(intent: Intent, key: String): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(key, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(key)
        }
    }

    private fun getParcelableUriList(intent: Intent, key: String): List<Uri> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(key, Uri::class.java) ?: emptyList()
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(key) ?: emptyList()
        }
    }

    private fun resolveFileName(uri: Uri): String {
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (idx >= 0) {
                            val name = cursor.getString(idx)
                            if (!name.isNullOrBlank()) return name
                        }
                    }
                }
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "shared_activity"
    }
}
