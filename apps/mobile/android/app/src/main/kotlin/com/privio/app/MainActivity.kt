package com.privio.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * SEC-005 : FLAG_SECURE appliqué à toute l'application dès la création de la fenêtre.
 * Bloque captures et enregistrements d'écran système, et masque l'aperçu dans les
 * applications récentes. Limite connue : inefficace contre un appareil rooté/compromis
 * ou une caméra externe (aucune promesse absolue n'est faite à l'utilisateur).
 *
 * Lot 4.1 : canal de notification « Messages » (contenu toujours générique, masqué
 * sur l'écran verrouillé).
 *
 * Lot 4.2 : FlutterFragmentActivity, exigée par l'empreinte digitale (local_auth).
 */
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
        createMessagesChannel()
    }

    private fun createMessagesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "privio_messages",
            "Messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Nouveaux messages (sans aucun contenu)"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
