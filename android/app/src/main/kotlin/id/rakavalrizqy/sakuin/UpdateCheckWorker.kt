package id.rakavalrizqy.sakuin

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Worker latar belakang sangat hemat baterai (dijadwalkan oleh Android WorkManager 1x/24 jam
 * hanya saat ada koneksi internet dan baterai tidak rendah).
 * Memakai header `If-None-Match` (ETag) agar ketika belum ada rilis baru, GitHub cukup
 * membalas `304 Not Modified` (0 byte body).
 */
class UpdateCheckWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {

    companion object {
        const val WORK_NAME = "sakuin_daily_update_check"
        const val PREFS_NAME = "sakuin_update_worker_prefs"
        const val KEY_ENABLED = "enabled"
        const val KEY_ETAG = "etag"
        const val KEY_LAST_NOTIFIED_TAG = "last_notified_tag"
        const val KEY_GITHUB_TOKEN = "github_token"
        private const val CHANNEL_ID = "sakuin_updates"
        private const val NOTIF_ID = 9401
        private const val LATEST_RELEASE_URL =
            "https://api.github.com/repos/RakaValrizqy/sakuin/releases/latest"
    }

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, true)) {
            return Result.success()
        }

        var conn: HttpURLConnection? = null
        try {
            val url = URL(LATEST_RELEASE_URL)
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 8000
                readTimeout = 8000
                setRequestProperty("Accept", "application/vnd.github+json")
                setRequestProperty("User-Agent", "Sakuin-Android-App")
                val token = prefs.getString(KEY_GITHUB_TOKEN, null)?.trim()
                if (!token.isNullOrEmpty()) {
                    setRequestProperty("Authorization", "Bearer $token")
                }
                val etag = prefs.getString(KEY_ETAG, null)?.trim()
                if (!etag.isNullOrEmpty()) {
                    setRequestProperty("If-None-Match", etag)
                }
            }

            val code = conn.responseCode
            if (code == HttpURLConnection.HTTP_NOT_MODIFIED) {
                return Result.success()
            }
            if (code != HttpURLConnection.HTTP_OK) {
                return Result.success()
            }

            val newEtag = conn.getHeaderField("ETag")
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)

            if (json.optBoolean("draft", false) || json.optBoolean("prerelease", false)) {
                return Result.success()
            }

            val tagName = json.optString("tag_name", "").trim()
            if (tagName.isEmpty()) return Result.success()

            val pkgInfo = applicationContext.packageManager
                .getPackageInfo(applicationContext.packageName, 0)
            val currentVersion = pkgInfo.versionName ?: "1.0.0"

            val editor = prefs.edit()
            if (!newEtag.isNullOrBlank()) {
                editor.putString(KEY_ETAG, newEtag)
            }

            if (compareVersions(tagName, currentVersion) > 0) {
                val lastNotified = prefs.getString(KEY_LAST_NOTIFIED_TAG, null)
                if (lastNotified != tagName) {
                    val releaseTitle = json.optString("name", "").trim()
                        .ifEmpty { "Sakuin $tagName" }
                    showUpdateNotification(tagName, releaseTitle)
                    editor.putString(KEY_LAST_NOTIFIED_TAG, tagName)
                }
            }
            editor.apply()
            return Result.success()
        } catch (_: Exception) {
            // Jangan retry agresif supaya baterai tetap hemat; akan dicek lagi di jadwal berikutnya.
            return Result.success()
        } finally {
            conn?.disconnect()
        }
    }

    private fun showUpdateNotification(tagName: String, releaseTitle: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                applicationContext,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) return
        }

        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Pembaruan Aplikasi Sakuin",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Memberitahu ketika versi baru Sakuin tersedia di GitHub"
            }
            manager.createNotificationChannel(channel)
        }

        val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            NOTIF_ID,
            launchIntent,
            pendingFlags,
        )

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Pembaruan $releaseTitle Tersedia")
            .setContentText("Ketuk untuk melihat apa yang baru & perbarui ke $tagName langsung dari aplikasi.")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "Versi terbaru $tagName sudah tersedia di GitHub. Ketuk untuk membuka Sakuin, melihat catatan perubahan, dan memperbarui tanpa uninstall."
                )
            )
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        manager.notify(NOTIF_ID, notification)
    }

    private fun compareVersions(remote: String, local: String): Int {
        fun parseParts(raw: String): List<Int> {
            var clean = raw.trim().lowercase()
            if (clean.startsWith("v")) clean = clean.substring(1)
            clean = clean.substringBefore("+").substringBefore("-")
            return clean.split(".").map { it.toIntOrNull() ?: 0 }
        }

        val r = parseParts(remote)
        val l = parseParts(local)
        val len = maxOf(r.size, l.size)
        for (i in 0 until len) {
            val rv = if (i < r.size) r[i] else 0
            val lv = if (i < l.size) l[i] else 0
            if (rv != lv) return rv.compareTo(lv)
        }
        return 0
    }
}
