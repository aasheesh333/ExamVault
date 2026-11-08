package app.examvault

import android.app.NotificationChannel
import android.app.NotificationManager
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
        const val CHANNEL_ID = "exam_alerts"
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
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

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
            // No sound override: respect whatever the user chose in system settings.
            setBypassDnd(false)
        }

        manager.createNotificationChannel(channel)
    }
}
