package app.examvault

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * Single-activity host.
 *
 * Deliberately thin — all navigation lives in Flutter. The one native job is
 * registering the result-day notification channel before the activity is
 * created, because FCM falls back to the default (low-importance) channel if the
 * channel id in the manifest does not exist yet, and a batched "your result is
 * out" notification is worthless.
 */
class MainActivity : FlutterActivity() {

    companion object {
        /**
         * Versioned channel id — DELIBERATELY not the old `exam_alerts`.
         *
         * Android freezes a channel's sound the moment it is created: the user
         * owns it afterwards, and an app cannot change or override it. Shipping
         * the custom chime therefore REQUIRES a new id; reusing the old one
         * would leave every existing install silently on the system default
         * sound. The legacy channel is removed below so the system settings
         * screen does not show two ExamVault entries.
         *
         * Keep this in sync with:
         *  - AndroidManifest default_notification_channel_id
         *  - the push dispatcher's android.notification.channel_id
         */
        const val CHANNEL_ID = "exam_alerts_v2"
        const val LEGACY_CHANNEL_ID = "exam_alerts"
        const val CHANNEL_NAME = "Result & admit card alerts"
        const val CHANNEL_DESCRIPTION =
            "Fires the moment a result, admit card or form deadline goes live."
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        createAlertChannel()
        super.onCreate(savedInstanceState)
    }

    private fun createAlertChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return

        // The pre-SFX channel is retired: it can never carry the custom sound,
        // and leaving it behind duplicates the app in system notification
        // settings.
        manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)

        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        // res/raw/exam_alert.wav — generated for this app (a two-note rising
        // chime), so there is no third-party audio licence to carry.
        val sound = Uri.parse(
            "${ContentResolver.SCHEME_ANDROID_RESOURCE}://$packageName/${R.raw.exam_alert}"
        )

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            // HIGH is the only importance that guarantees heads-up delivery while
            // the phone is idle. A result alert that arrives 40 minutes late has
            // zero value.
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = CHANNEL_DESCRIPTION
            enableLights(true)
            enableVibration(true)
            setShowBadge(true)
            // The custom SFX. AudioAttributes matter: without USAGE_NOTIFICATION
            // the tone follows the media volume stream and can be silent while
            // the phone is on silent-for-media.
            setSound(
                sound,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            // A short chime, not an alarm: do not pierce Do Not Disturb.
            setBypassDnd(false)
        }

        manager.createNotificationChannel(channel)
    }
}
