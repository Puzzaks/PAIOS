package page.puzzak.geminilocal

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAssistantOpenIntent(intent)
        registerHeadlessMeshHandler(applicationContext)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAssistantOpenIntent(intent)
    }

    private fun handleAssistantOpenIntent(intent: Intent?) {
        val messagesJson = intent?.getStringExtra("open_chat_messages")
        val unarchived = intent?.getBooleanExtra("open_chat_unarchived", true) ?: true
        if (!messagesJson.isNullOrBlank()) {
            intent.removeExtra("open_chat_messages")
            FlutterLocalAiPlugin.deliverAssistantChat(messagesJson, unarchived)
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        registerHeadlessMeshHandler(applicationContext)

        try {
            flutterEngine.plugins.add(FlutterLocalAiPlugin(this))
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error registering plugin flutter_local_ai", e)
        }

        try {
            flutterEngine.plugins.add(FileAccessPlugin())
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error registering FileAccessPlugin", e)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "page.puzzak.paios/mesh"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBatteryStatus" -> {
                    try {
                        result.success(readBatteryStatus())
                    } catch (e: Exception) {
                        result.error("BATTERY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readBatteryStatus(): Map<String, Any> {
        val snapshot = InternalToolsHelper.readBatteryStatusSnapshot(applicationContext)
        return mapOf(
            "level" to snapshot.level,
            "charging" to snapshot.charging,
            "status" to snapshot.status,
        )
    }

    companion object {
        private val overlayMethods = setOf("query_local_ai", "open_assistant_bubble")

        @JvmStatic
        fun registerHeadlessMeshHandler(context: Context) {
            val appContext = context.applicationContext
            com.puzzak.m3x_mesh.M3xMeshContentProvider.headlessHandler = { caller, payload, callback ->
                val json = try {
                    org.json.JSONObject(payload)
                } catch (_: Exception) {
                    null
                }
                val method = json
                    ?.optString("method", json.optString("name", json.optString("tool", "")))
                    ?.trim()
                    .orEmpty()
                if (method in overlayMethods) {
                    val paramsObj = json?.optJSONObject("params") ?: json?.optJSONObject("arguments")
                    val isInteractive = method == "open_assistant_bubble" ||
                        json?.optBoolean("interactive_bubble", false) == true ||
                        paramsObj?.optBoolean("interactive_bubble", false) == true
                    MeshOverlayActivity.pendingCallback = callback
                    val intent = Intent(appContext, MeshOverlayActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION
                        putExtra("caller", caller)
                        putExtra("payload", payload)
                        if (isInteractive) {
                            putExtra("interactive_bubble", true)
                        }
                    }
                    appContext.startActivity(intent)
                    true
                } else {
                    false
                }
            }
        }
    }
}
