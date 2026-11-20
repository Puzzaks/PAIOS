package page.puzzak.geminilocal

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import androidx.core.content.edit
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class FileAccessPlugin : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var activity: Activity? = null
    private var pendingResult: MethodChannel.Result? = null
    private lateinit var prefs: SharedPreferences
    private var pluginScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    companion object {
        private const val CHANNEL = "page.puzzak.geminilocal/file_access"
        private const val REQUEST_PICK_DIR = 4201
        private const val PREF_NAME = "file_access_prefs"
        private const val PREF_TREE_URI = "prompt_dir_uri"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        pluginScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        prefs = appContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        channel.setMethodCallHandler { call, result -> handleCall(call, result) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        pluginScope.cancel()
    }

    // ── ActivityAware ─────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    // ── ActivityResultListener ────────────────────────────────────────────────

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_DIR) return false
        val result = pendingResult ?: return true
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }

        val treeUri = data.data!!
        // Take persistent read+write permission so access survives restarts
        appContext.contentResolver.takePersistableUriPermission(
            treeUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        prefs.edit { putString(PREF_TREE_URI, treeUri.toString()) }
        result.success(getDisplayPath(treeUri))
        return true
    }

    // ── Method dispatch ───────────────────────────────────────────────────────

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> pickDirectory(result)
            "getDirectoryDisplayPath" -> getDirectoryDisplayPath(result)
            "hasDirectory" -> result.success(savedTreeUri() != null)
            "writeFile" -> {
                val name = call.argument<String>("name") ?: return result.error("BAD_ARGS", "name missing", null)
                val content = call.argument<String>("content") ?: ""
                writeFile(name, content, result)
            }
            "readFile" -> {
                val name = call.argument<String>("name") ?: return result.error("BAD_ARGS", "name missing", null)
                readFile(name, result)
            }
            "listFiles" -> listFiles(result)
            "deleteFile" -> {
                val name = call.argument<String>("name") ?: return result.error("BAD_ARGS", "name missing", null)
                deleteFile(name, result)
            }
            "renameFile" -> {
                val oldName = call.argument<String>("oldName") ?: return result.error("BAD_ARGS", "oldName missing", null)
                val newName = call.argument<String>("newName") ?: return result.error("BAD_ARGS", "newName missing", null)
                renameFile(oldName, newName, result)
            }
            else -> result.notImplemented()
        }
    }

    // ── SAF operations ────────────────────────────────────────────────────────

    private fun pickDirectory(result: MethodChannel.Result) {
        val act = activity ?: return result.error("NO_ACTIVITY", "No activity attached", null)
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        act.startActivityForResult(intent, REQUEST_PICK_DIR)
    }

    private fun getDirectoryDisplayPath(result: MethodChannel.Result) {
        val uri = savedTreeUri()
        if (uri == null) { result.success(null); return }
        result.success(getDisplayPath(uri))
    }

    private fun writeFile(filename: String, content: String, result: MethodChannel.Result) {
        val uri = savedTreeUri() ?: return result.error("NO_DIR", "No directory selected", null)
        val ctx = appContext
        pluginScope.launch {
            try {
                val dir = DocumentFile.fromTreeUri(ctx, uri)
                if (dir == null) {
                    withContext(Dispatchers.Main) { result.error("BAD_URI", "Cannot open directory", null) }
                    return@launch
                }
                val existing = dir.findFile(filename)
                val file = if (existing != null && !existing.isDirectory) {
                    existing
                } else {
                    dir.createFile("text/markdown", filename)
                }
                if (file == null) {
                    withContext(Dispatchers.Main) { result.error("CREATE_FAILED", "Cannot create $filename", null) }
                    return@launch
                }
                val stream = ctx.contentResolver.openOutputStream(file.uri, "wt")
                if (stream == null) {
                    withContext(Dispatchers.Main) { result.error("WRITE_FAILED", "Cannot open output stream", null) }
                    return@launch
                }
                stream.use { out ->
                    out.write(content.toByteArray(Charsets.UTF_8))
                }
                withContext(Dispatchers.Main) { result.success(true) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.error("WRITE_ERROR", e.message, null) }
            }
        }
    }

    private fun readFile(filename: String, result: MethodChannel.Result) {
        val uri = savedTreeUri() ?: return result.error("NO_DIR", "No directory selected", null)
        val ctx = appContext
        pluginScope.launch {
            try {
                val dir = DocumentFile.fromTreeUri(ctx, uri)
                if (dir == null) {
                    withContext(Dispatchers.Main) { result.error("BAD_URI", "Cannot open directory", null) }
                    return@launch
                }
                val file = dir.findFile(filename)
                if (file == null) {
                    withContext(Dispatchers.Main) { result.success(null) }
                    return@launch
                }
                val content = ctx.contentResolver.openInputStream(file.uri)?.use { stream ->
                    stream.bufferedReader(Charsets.UTF_8).readText()
                }
                withContext(Dispatchers.Main) { result.success(content) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.error("READ_ERROR", e.message, null) }
            }
        }
    }

    private fun listFiles(result: MethodChannel.Result) {
        val uri = savedTreeUri() ?: return result.success(emptyList<String>())
        val ctx = appContext
        pluginScope.launch {
            val names = try {
                val dir = DocumentFile.fromTreeUri(ctx, uri)
                dir?.listFiles()
                    ?.filter { it.isFile && (it.name?.endsWith(".md", ignoreCase = true) == true) }
                    ?.mapNotNull { it.name }
                    ?: emptyList()
            } catch (_: Exception) {
                emptyList()
            }
            withContext(Dispatchers.Main) { result.success(names) }
        }
    }

    private fun deleteFile(filename: String, result: MethodChannel.Result) {
        val uri = savedTreeUri() ?: return result.success(false)
        val ctx = appContext
        pluginScope.launch {
            val deleted = try {
                val dir = DocumentFile.fromTreeUri(ctx, uri)
                dir?.findFile(filename)?.delete() ?: false
            } catch (_: Exception) {
                false
            }
            withContext(Dispatchers.Main) { result.success(deleted) }
        }
    }

    private fun renameFile(oldName: String, newName: String, result: MethodChannel.Result) {
        val uri = savedTreeUri() ?: return result.success(false)
        val ctx = appContext
        pluginScope.launch {
            val renamed = try {
                val dir = DocumentFile.fromTreeUri(ctx, uri)
                dir?.findFile(oldName)?.renameTo(newName) ?: false
            } catch (_: Exception) {
                false
            }
            withContext(Dispatchers.Main) { result.success(renamed) }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun savedTreeUri(): Uri? {
        val s = prefs.getString(PREF_TREE_URI, null) ?: return null
        return Uri.parse(s)
    }

    private fun getDisplayPath(treeUri: Uri): String {
        // Decode SAF tree URI into a human-readable path, e.g. "Internal Storage › Documents › Prompts"
        val path = treeUri.lastPathSegment ?: return treeUri.toString()
        return path.replace("primary:", "/sdcard/").replace(":", "/")
    }
}
