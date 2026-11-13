package page.puzzak.geminilocal

import android.content.Intent
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAssistantOpenIntent(intent)
        registerMeshHeadlessHandler()
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

        registerMeshHeadlessHandler()

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
    }

    private val overlayMethods = setOf("query_local_ai", "open_assistant_bubble")

    private fun registerMeshHeadlessHandler() {
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
                val intent = Intent(this, MeshOverlayActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION
                    putExtra("caller", caller)
                    putExtra("payload", payload)
                    if (isInteractive) {
                        putExtra("interactive_bubble", true)
                    }
                }
                startActivity(intent)
                true
            } else {
                false
            }
        }
    }
}
