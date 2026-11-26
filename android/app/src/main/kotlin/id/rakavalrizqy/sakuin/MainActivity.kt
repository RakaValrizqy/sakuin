package id.rakavalrizqy.sakuin

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.max

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val SECURITY_CHANNEL = "id.rakavalrizqy.sakuin/security"
        private const val UPDATER_CHANNEL = "id.rakavalrizqy.sakuin/updater"
        private const val RECEIPT_CHANNEL = "id.rakavalrizqy.sakuin/receipt"
        private const val REQ_CAPTURE_PHOTO = 7101
        private const val REQ_PICK_IMAGE = 7102
    }

    private var receiptChannel: MethodChannel? = null
    private var pendingImageResult: MethodChannel.Result? = null
    private var currentCameraFile: File? = null
    private var pendingSharedImagePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingShareIntent(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingShareIntent(intent, notifyFlutter = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecureFlag" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppInfo" -> {
                        try {
                            val pkgInfo = packageManager.getPackageInfo(packageName, 0)
                            val versionCode = PackageInfoCompat.getLongVersionCode(pkgInfo)
                            val info = mapOf(
                                "versionName" to (pkgInfo.versionName ?: "1.0.0"),
                                "versionCode" to versionCode.toInt(),
                                "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
                            )
                            result.success(info)
                        } catch (e: Exception) {
                            result.error("APP_INFO_ERROR", e.message, null)
                        }
                    }
                    "canRequestPackageInstalls" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            result.success(packageManager.canRequestPackageInstalls())
                        } else {
                            result.success(true)
                        }
                    }
                    "openInstallPermissionSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "Path APK kosong", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "File APK tidak ditemukan", null)
                                return@setMethodCallHandler
                            }
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.update_fileprovider",
                                file,
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }
                    "configureBackgroundUpdateCheck" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val token = call.argument<String>("githubToken")
                        try {
                            configureDailyUpdateWorker(enabled, token)
                            result.success(true)
                        } catch (e: Throwable) {
                            result.error("WORKER_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        receiptChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECEIPT_CHANNEL)
        receiptChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "captureReceiptPhoto" -> launchCameraForReceipt(result)
                "pickReceiptImage" -> launchGalleryForReceipt(result)
                "recognizeText" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Path gambar kosong", null)
                    } else {
                        runOnDeviceOcr(filePath, result)
                    }
                }
                "prepareImageForAi" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Path gambar kosong", null)
                    } else {
                        try {
                            val prepared = compressReceiptForAi(File(filePath))
                            result.success(prepared.absolutePath)
                        } catch (e: Exception) {
                            result.error("COMPRESS_ERROR", e.message, null)
                        }
                    }
                }
                "getPendingSharedImage" -> {
                    val path = pendingSharedImagePath
                    pendingSharedImagePath = null
                    result.success(path)
                }
                "cleanupReceiptCache" -> {
                    cleanupReceiptCacheDir()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun configureDailyUpdateWorker(enabled: Boolean, githubToken: String?) {
        val prefs = getSharedPreferences(UpdateCheckWorker.PREFS_NAME, MODE_PRIVATE)
        val editor = prefs.edit().putBoolean(UpdateCheckWorker.KEY_ENABLED, enabled)
        if (githubToken == null) {
            editor.remove(UpdateCheckWorker.KEY_GITHUB_TOKEN)
        } else {
            val cleaned = githubToken.trim()
            if (cleaned.isEmpty()) {
                editor.remove(UpdateCheckWorker.KEY_GITHUB_TOKEN)
            } else {
                editor.putString(UpdateCheckWorker.KEY_GITHUB_TOKEN, cleaned)
            }
        }
        // Reset ETag saat token berubah agar cek berikutnya mendapat respons segar
        editor.remove(UpdateCheckWorker.KEY_ETAG)
        editor.apply()

        val wm = WorkManager.getInstance(applicationContext)
        if (!enabled) {
            wm.cancelUniqueWork(UpdateCheckWorker.WORK_NAME)
            return
        }

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()

        val request = PeriodicWorkRequestBuilder<UpdateCheckWorker>(24, TimeUnit.HOURS)
            .setConstraints(constraints)
            .setInitialDelay(12, TimeUnit.HOURS)
            .build()

        wm.enqueueUniquePeriodicWork(
            UpdateCheckWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request,
        )
    }

    private fun receiptsDir(): File {
        val dir = File(cacheDir, "receipts")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun launchCameraForReceipt(result: MethodChannel.Result) {
        if (pendingImageResult != null) {
            result.error("BUSY", "Pengambilan gambar sebelumnya masih berjalan", null)
            return
        }
        try {
            val photoFile = File(receiptsDir(), "cam_${System.currentTimeMillis()}.jpg")
            currentCameraFile = photoFile
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.update_fileprovider",
                photoFile,
            )
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, uri)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            pendingImageResult = result
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_CAPTURE_PHOTO)
        } catch (e: Exception) {
            currentCameraFile = null
            pendingImageResult = null
            result.error("CAMERA_ERROR", "Tidak dapat membuka kamera: ${e.message}", null)
        }
    }

    private fun launchGalleryForReceipt(result: MethodChannel.Result) {
        if (pendingImageResult != null) {
            result.error("BUSY", "Pengambilan gambar sebelumnya masih berjalan", null)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
                addCategory(Intent.CATEGORY_OPENABLE)
            }
            pendingImageResult = result
            @Suppress("DEPRECATION")
            startActivityForResult(
                Intent.createChooser(intent, "Pilih foto struk"),
                REQ_PICK_IMAGE,
            )
        } catch (e: Exception) {
            pendingImageResult = null
            result.error("GALLERY_ERROR", "Tidak dapat membuka galeri: ${e.message}", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_CAPTURE_PHOTO) {
            val res = pendingImageResult
            pendingImageResult = null
            val file = currentCameraFile
            currentCameraFile = null
            if (resultCode == Activity.RESULT_OK && file != null && file.exists() && file.length() > 0) {
                res?.success(file.absolutePath)
            } else {
                file?.delete()
                res?.success(null)
            }
            return
        }
        if (requestCode == REQ_PICK_IMAGE) {
            val res = pendingImageResult
            pendingImageResult = null
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                val copied = copyUriToReceiptCache(uri, "pick")
                res?.success(copied?.absolutePath)
            } else {
                res?.success(null)
            }
            return
        }
    }

    private fun handleIncomingShareIntent(intent: Intent?, notifyFlutter: Boolean) {
        if (intent == null) return
        try {
            if (intent.action == Intent.ACTION_SEND && intent.type?.startsWith("image/") == true) {
                @Suppress("DEPRECATION")
                val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                if (uri != null) {
                    val copied = copyUriToReceiptCache(uri, "shared")
                    if (copied != null) {
                        val path = copied.absolutePath
                        if (notifyFlutter && receiptChannel != null) {
                            runOnUiThread {
                                receiptChannel?.invokeMethod("onSharedImage", path)
                            }
                        } else {
                            pendingSharedImagePath = path
                        }
                    }
                }
            }
        } catch (_: Throwable) {
            // Jangan pernah crash saat memproses intent dari aplikasi lain
        }
    }

    private fun copyUriToReceiptCache(uri: Uri, prefix: String): File? {
        return try {
            val outFile = File(receiptsDir(), "${prefix}_${System.currentTimeMillis()}.jpg")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
            } ?: return null
            if (outFile.length() > 0) outFile else null
        } catch (_: Exception) {
            null
        }
    }

    private fun compressReceiptForAi(inputFile: File): File {
        val optsBounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(inputFile.absolutePath, optsBounds)
        val maxDim = 1280
        var sampleSize = 1
        while ((optsBounds.outWidth / sampleSize) > maxDim * 2 ||
            (optsBounds.outHeight / sampleSize) > maxDim * 2
        ) {
            sampleSize *= 2
        }
        val optsDecode = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val rawBitmap = BitmapFactory.decodeFile(inputFile.absolutePath, optsDecode)
            ?: return inputFile

        val scale = minOf(
            1.0f,
            maxDim.toFloat() / max(rawBitmap.width, rawBitmap.height).toFloat(),
        )
        val finalBitmap = if (scale < 0.99f) {
            Bitmap.createScaledBitmap(
                rawBitmap,
                max(1, (rawBitmap.width * scale).toInt()),
                max(1, (rawBitmap.height * scale).toInt()),
                true,
            )
        } else {
            rawBitmap
        }

        val outFile = File(receiptsDir(), "ai_${System.currentTimeMillis()}.jpg")
        FileOutputStream(outFile).use { out ->
            finalBitmap.compress(Bitmap.CompressFormat.JPEG, 78, out)
        }
        if (finalBitmap !== rawBitmap) finalBitmap.recycle()
        rawBitmap.recycle()
        return outFile
    }

    /**
     * Jalankan Google ML Kit OCR (100% lokal) lalu susun ulang baris-baris struk
     * berdasarkan koordinat Y bounding box agar nama barang di sisi kiri dan harga di sisi kanan
     * tetap menyatu dalam satu baris teks yang rapi.
     */
    private fun runOnDeviceOcr(filePath: String, result: MethodChannel.Result) {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "File gambar tidak ditemukan", null)
                return
            }
            val image = InputImage.fromFilePath(this, Uri.fromFile(file))
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    val rows = reconstructReceiptLines(visionText)
                    recognizer.close()
                    result.success(rows)
                }
                .addOnFailureListener { e ->
                    recognizer.close()
                    result.error("OCR_ERROR", e.message ?: "Gagal membaca teks dari gambar", null)
                }
        } catch (e: Throwable) {
            result.error("OCR_ERROR", e.message, null)
        }
    }

    private fun reconstructReceiptLines(visionText: Text): String {
        val allLines = mutableListOf<Text.Line>()
        for (block in visionText.textBlocks) {
            for (line in block.lines) {
                if (line.text.isNotBlank()) {
                    allLines.add(line)
                }
            }
        }
        if (allLines.isEmpty()) return visionText.text

        // Urutkan dari atas ke bawah berdasarkan centerY
        val sorted = allLines.sortedBy { it.boundingBox?.centerY() ?: 0 }
        val rowGroups = mutableListOf<MutableList<Text.Line>>()

        for (line in sorted) {
            val box = line.boundingBox
            if (box == null) {
                rowGroups.add(mutableListOf(line))
                continue
            }
            val cy = box.centerY()
            val h = max(box.height(), 12)
            var matchedGroup: MutableList<Text.Line>? = null
            for (group in rowGroups) {
                val refBox = group.first().boundingBox ?: continue
                val refCy = refBox.centerY()
                val refH = max(refBox.height(), 12)
                val tolerance = (max(h, refH) * 0.55f).toInt()
                if (abs(cy - refCy) <= tolerance) {
                    matchedGroup = group
                    break
                }
            }
            if (matchedGroup != null) {
                matchedGroup.add(line)
            } else {
                rowGroups.add(mutableListOf(line))
            }
        }

        val sb = StringBuilder()
        for (group in rowGroups) {
            val orderedRow = group.sortedBy { it.boundingBox?.left ?: 0 }
            val joined = orderedRow.joinToString("  ") { it.text.trim() }
            if (joined.isNotBlank()) {
                sb.appendLine(joined)
            }
        }
        return sb.toString().trim()
    }

    private fun cleanupReceiptCacheDir() {
        try {
            val dir = File(cacheDir, "receipts")
            if (dir.exists()) {
                dir.listFiles()?.forEach { it.delete() }
            }
        } catch (_: Exception) {}
    }
}
