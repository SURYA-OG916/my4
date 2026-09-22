package com.example.my4

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

private const val TAG = "MY4Notif"

// Only notifications from these apps are ever captured. Everything else is ignored.
// "com.android.shell" is TEST ONLY: it lets `adb shell cmd notification post` work on
// the emulator. Remove it before any real release.
private val ALLOWED_PACKAGES = setOf(
    "com.google.android.apps.nbu.paisa.user", // Google Pay
    "com.phonepe.app",                         // PhonePe
    "net.one97.paytm",                         // Paytm
    "in.org.npci.upiapp",                      // BHIM
    "com.dreamplug.androidapp",                // CRED
    "com.samsung.android.spaymini",            // Samsung Wallet (Samsung Pay Mini)
    "com.samsung.android.spay",                // Samsung Pay / Wallet (older package name)
    "indwin.c3.shareapp",                      // Slice
    "com.whatsapp",                            // WhatsApp Pay (payments only, see below)
    "com.whatsapp.w4b",                        // WhatsApp Business
    "com.android.shell"                        // TEST ONLY
)

// WhatsApp also posts every chat message. For these packages we apply extra
// filters so that chats are dropped before their text is ever read or stored.
private val WHATSAPP_PACKAGES = setOf("com.whatsapp", "com.whatsapp.w4b")

// Wording that reads like a money movement.
private val WHATSAPP_PAYMENT_PHRASE = Regex(
    "(?i)\\b(you (have )?(paid|received|sent)|(paid|sent) you|" +
        "payment (of|to|from|received|successful|sent|failed)|" +
        "money (sent|received)|credited|debited)\\b"
)

// "Name sent ₹1.00 to You" / "You sent ₹1.00 to Name" style wording.
private val WHATSAPP_AMOUNT_MOVE =
    Regex("(?i)\\b(sent|paid|received)\\s+(₹|rs\\.?|inr)\\s*[0-9]")

// A notification is only worth keeping if it mentions an amount of money
// (₹250, Rs 250, Rs. 1,250.50, INR 99). This drops chat messages, "tap to
// reveal" rewards and other notifications that can never be a transaction.
private val AMOUNT_PATTERN = Regex("(?i)(₹|\\brs\\.?|\\binr)\\s*[0-9]")

// WhatsApp chat notifications use the messaging category / MessagingStyle.
private fun isChatNotification(notification: Notification): Boolean {
    if (notification.category == Notification.CATEGORY_MESSAGE) return true
    val template = notification.extras?.getString(Notification.EXTRA_TEMPLATE) ?: ""
    return template.contains("MessagingStyle")
}

class MyNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (!ALLOWED_PACKAGES.contains(sbn.packageName)) return

        val notification = sbn.notification ?: return

        // Skip "N new notifications" style group summaries; the real ones arrive separately.
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return

        val extras = notification.extras ?: return
        val isWhatsApp = WHATSAPP_PACKAGES.contains(sbn.packageName)

        // Only the title is read before the chat check, so chat text is never
        // touched. WhatsApp payment notifications use the title "Payment".
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val titleIsPayment = isWhatsApp && title.trim().equals("Payment", ignoreCase = true)

        if (isWhatsApp && !titleIsPayment && isChatNotification(notification)) {
            Log.d(TAG, "WhatsApp notification dropped: chat-style (category=${notification.category})")
            return
        }

        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val text = bigText
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: ""

        if (title.isBlank() && text.isBlank()) return

        // WhatsApp: outside the "Payment" title, keep only what reads like a payment.
        if (isWhatsApp && !titleIsPayment) {
            val looksLikePayment = WHATSAPP_PAYMENT_PHRASE.containsMatchIn("$title $text") ||
                WHATSAPP_AMOUNT_MOVE.containsMatchIn(text)
            if (!looksLikePayment) {
                Log.d(TAG, "WhatsApp notification dropped: no payment wording")
                return
            }
        }

        // No amount mentioned -> not a payment notification.
        if (!AMOUNT_PATTERN.containsMatchIn("$title $text")) return

        NotificationQueue.add(
            applicationContext,
            sbn.packageName,
            title,
            text,
            sbn.postTime
        )
    }
}

// Simple persistent queue backed by app-private SharedPreferences (JSON array).
// The Flutter side reads it through the "my4/notifications" MethodChannel.
object NotificationQueue {
    private const val PREFS = "my4_notification_queue"
    private const val KEY = "queue"
    private const val MAX_ITEMS = 200
    private const val DUPLICATE_WINDOW_MS = 60_000L

    private val lock = Any()

    fun add(context: Context, pkg: String, title: String, text: String, postTime: Long) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val current = read(prefs)

            // Apps sometimes re-post the same notification; ignore near-identical repeats.
            for (i in 0 until current.length()) {
                val existing = current.getJSONObject(i)
                val samePackage = existing.optString("package") == pkg
                val sameTitle = existing.optString("title") == title
                val sameText = existing.optString("text") == text
                val closeInTime =
                    Math.abs(postTime - existing.optLong("postTime")) < DUPLICATE_WINDOW_MS
                if (samePackage && sameTitle && sameText && closeInTime) return
            }

            val item = JSONObject()
                .put("id", "$pkg|$postTime")
                .put("package", pkg)
                .put("title", title)
                .put("text", text)
                .put("postTime", postTime)
            current.put(item)

            val result = if (current.length() > MAX_ITEMS) {
                val trimmed = JSONArray()
                for (i in (current.length() - MAX_ITEMS) until current.length()) {
                    trimmed.put(current.get(i))
                }
                trimmed
            } else {
                current
            }

            prefs.edit().putString(KEY, result.toString()).apply()
        }
    }

    fun getAll(context: Context): String {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return read(prefs).toString()
        }
    }

    fun clear(context: Context) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit().remove(KEY).apply()
        }
    }

    private fun read(prefs: android.content.SharedPreferences): JSONArray {
        return try {
            JSONArray(prefs.getString(KEY, "[]"))
        } catch (e: Exception) {
            JSONArray()
        }
    }
}