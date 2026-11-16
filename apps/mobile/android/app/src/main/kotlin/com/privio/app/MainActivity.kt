package com.privio.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
 *
 * Lot 9.1b : canal « privio/call » — pendant un appel, l'écran d'appel s'affiche
 * par-dessus l'écran de verrouillage du téléphone (réduit, le verrouillage revient) et
 * l'écran s'éteint à l'oreille (capteur de proximité, écouteur seulement).
 *
 * Lot 9.2 : appel vidéo → petite fenêtre au-dessus des autres applications quand on quitte
 * Privio (« pip »), signalée à Flutter (« pipChanged ») qui n'y montre que l'image.
 *
 * Lot 5.6 : canal « privio/device » — modèle du téléphone et version d'Android.
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

    private var proximityLock: PowerManager.WakeLock? = null
    private var callChannel: MethodChannel? = null
    private var pipAllowed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        callChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privio/call")
        callChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "pip" -> {
                        setPipAllowed(call.arguments == true)
                        result.success(null)
                    }
                    "overLock" -> {
                        setOverLock(call.arguments == true)
                        result.success(null)
                    }
                    "proximity" -> {
                        setProximity(call.arguments == true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Lot 5.6 : modèle et version d'Android, pour l'assistance (console).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "privio/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "info") {
                    val maker = Build.MANUFACTURER.orEmpty().replaceFirstChar { it.uppercase() }
                    val model = Build.MODEL.orEmpty()
                    val name = if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model"
                    result.success(mapOf("model" to name.trim().take(64), "os" to Build.VERSION.RELEASE))
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun pipParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val b = PictureInPictureParams.Builder().setAspectRatio(Rational(9, 16))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) b.setAutoEnterEnabled(pipAllowed)
        return b.build()
    }

    private fun setPipAllowed(on: Boolean) {
        pipAllowed = on
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                pipParams()?.let { setPictureInPictureParams(it) }
            } catch (_: Exception) {
                // Fenêtre réduite indisponible sur ce téléphone.
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAllowed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S
        ) {
            try {
                pipParams()?.let { enterPictureInPictureMode(it) }
            } catch (_: Exception) {
                // Fenêtre réduite refusée (réglage du téléphone) : l'appel continue.
            }
        }
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPip, newConfig)
        callChannel?.invokeMethod("pipChanged", inPip)
    }

    private fun setOverLock(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) window.addFlags(flags) else window.clearFlags(flags)
        }
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun setProximity(on: Boolean) {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (on) {
            if (proximityLock?.isHeld == true) return
            if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
            proximityLock = pm.newWakeLock(
                PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                "privio:appel",
            ).apply { acquire(3 * 60 * 60 * 1000L) }
        } else {
            proximityLock?.let { if (it.isHeld) it.release() }
            proximityLock = null
        }
    }

    override fun onDestroy() {
        setProximity(false)
        super.onDestroy()
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
