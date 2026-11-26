package id.rakavalrizqy.sakuin

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Listener notifikasi Android 100% lokal & hemat baterai.
 * Hanya memproses notifikasi dari aplikasi bank / e-wallet Indonesia yang dikenal,
 * dan hanya aktif jika pengguna mengaktifkannya di dalam Sakuin.
 * Data tidak pernah dikirim ke server mana pun — hanya disimpan sementara ke antrean lokal.
 */
class SakuinNotificationListener : NotificationListenerService() {

    companion object {
        const val PREFS_NAME = "sakuin_notif_listener_prefs"
        const val KEY_ENABLED = "enabled"
        const val QUEUE_FILE_NAME = "pending_notif_qris.json"
        private const val MAX_QUEUE_ITEMS = 100
        private val FILE_LOCK = Any()

        private val ALLOWED_PACKAGES = setOf(
            "id.bmri.livin",
            "com.bca",
            "com.bca.mybca.omni.android",
            "id.co.bri.brimo",
            "src.com.bni",
            "id.bni.wondr",
            "com.bsm.activity2",
            "id.co.bankbsi.byond",
            "com.gojek.app",
            "com.gojek.gopay",
            "ovo.id",
            "id.dana",
            "com.shopee.id",
            "com.shopeepay.id",
            "id.co.bankbkemobile.digitalbank", // SeaBank
            "com.jago.digitalBanking",
            "com.bcadigital.blu",
            "id.co.cimbniaga.mobile.android",
            "com.btpn.dc", // Jenius
            "com.telkom.mwallet", // LinkAja
            "net.myinfosys.PermataMobileX",
            "com.allo.bank",
            "com.bnc.finance", // Neo Bank
            "com.ocbc.mobile",
            "id.co.danamon.dbankpro",
            "id.superbank.app",
            "id.krom.bank",
        )

        fun consumeQueuedNotifications(context: Context): List<Map<String, Any>> {
            synchronized(FILE_LOCK) {
                val file = File(context.filesDir, QUEUE_FILE_NAME)
                if (!file.exists()) return emptyList()
                return try {
                    val raw = file.readText()
                    file.delete()
                    if (raw.isBlank()) return emptyList()
                    val arr = JSONArray(raw)
                    val out = mutableListOf<Map<String, Any>>()
                    for (i in 0 until arr.length()) {
                        val obj = arr.optJSONObject(i) ?: continue
                        out.add(
                            mapOf(
                                "packageName" to obj.optString("packageName", ""),
                                "title" to obj.optString("title", ""),
                                "text" to obj.optString("text", ""),
                                "timestamp" to obj.optLong("timestamp", System.currentTimeMillis()),
                            ),
                        )
                    }
                    out
                } catch (_: Throwable) {
                    file.delete()
                    emptyList()
                }
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        try {
            if (sbn == null) return
            val pkg = sbn.packageName ?: return
            if (!ALLOWED_PACKAGES.contains(pkg)) return

            val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_ENABLED, false)) return

            val extras = sbn.notification?.extras ?: return
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
            val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim()
            val plainText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""
            val bodyText = if (!bigText.isNullOrBlank()) bigText else plainText

            if (title.isBlank() && bodyText.isBlank()) return

            // Filter cepat: wajib ada tanda nominal (Rp / IDR / angka ribuan) agar notifikasi non-transaksi langsung dibuang
            val combined = "$title $bodyText"
            if (!combined.contains("Rp", ignoreCase = true) &&
                !combined.contains("IDR", ignoreCase = true)
            ) {
                return
            }

            appendToLocalQueue(
                packageName = pkg,
                title = title,
                text = bodyText,
                timestamp = sbn.postTime.takeIf { it > 0 } ?: System.currentTimeMillis(),
            )
        } catch (_: Throwable) {
            // Jangan pernah crash proses listener sistem Android
        }
    }

    private fun appendToLocalQueue(
        packageName: String,
        title: String,
        text: String,
        timestamp: Long,
    ) {
        synchronized(FILE_LOCK) {
            val file = File(applicationContext.filesDir, QUEUE_FILE_NAME)
            val arr = try {
                if (file.exists()) JSONArray(file.readText()) else JSONArray()
            } catch (_: Throwable) {
                JSONArray()
            }

            // Dedup notifikasi identik dalam rentang 2 menit (Android sering update/re-post notif sama)
            for (i in 0 until arr.length()) {
                val existing = arr.optJSONObject(i) ?: continue
                if (existing.optString("packageName") == packageName &&
                    existing.optString("title") == title &&
                    existing.optString("text") == text &&
                    kotlin.math.abs(existing.optLong("timestamp") - timestamp) < 120_000L
                ) {
                    return
                }
            }

            val entry = JSONObject().apply {
                put("packageName", packageName)
                put("title", title)
                put("text", text)
                put("timestamp", timestamp)
            }
            arr.put(entry)

            // Batasi ukuran antrean maksimal 100 item terbaru
            val trimmed = if (arr.length() > MAX_QUEUE_ITEMS) {
                val sliced = JSONArray()
                for (i in (arr.length() - MAX_QUEUE_ITEMS) until arr.length()) {
                    sliced.put(arr.get(i))
                }
                sliced
            } else {
                arr
            }

            file.writeText(trimmed.toString())
        }
    }
}
