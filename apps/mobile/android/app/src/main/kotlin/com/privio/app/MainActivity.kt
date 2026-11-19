package com.privio.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
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
 *
 * Lot 9.3 : « callAudio » — pendant un appel, touches de volume sur le flux d'appel.
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
                    "callAudio" -> {
                        setCallAudio(call.arguments == true)
                        result.success(null)
                    }
                    "audioRoute" -> {
                        setAudioRoute(call.arguments as? String ?: "earpiece")
                        result.success(null)
                    }
                    "audioState" -> result.success(audioState())
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
                } else if (call.method == "sinceStart") {
                    // Lot 6.1 : temps écoulé depuis le lancement du processus (mesures de vitesse).
                    result.success(SystemClock.uptimeMillis() - Process.getStartUptimeMillis())
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

    /**
     * Lot 9.3 : pendant un appel, les touches de volume règlent le flux d'appel (et non
     * celui des médias) ; un volume d'appel très bas (moins de 40 %) est remonté à 60 %.
     */
    private fun setCallAudio(on: Boolean) {
        if (!on) {
            volumeControlStream = AudioManager.USE_DEFAULT_STREAM_TYPE
            audioHandler.removeCallbacksAndMessages(null)
            try {
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) am.clearCommunicationDevice()
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = false
            } catch (_: Exception) {
                // Ignoré.
            }
            callAudioOn = false
            lastRoute = null
            // Après la fin de l'appel, le téléphone revient en mode normal (musique, vidéos).
            audioHandler.postDelayed({
                if (callAudioOn) return@postDelayed
                try {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    if (am.mode == AudioManager.MODE_IN_COMMUNICATION) am.mode = AudioManager.MODE_NORMAL
                } catch (_: Exception) {
                    // Ignoré.
                }
            }, 800)
            return
        }
        callAudioOn = true
        // Sortie choisie avant le début de l'appel (appel vidéo : haut-parleur d'emblée).
        lastRoute?.let { setAudioRoute(it) }
        volumeControlStream = AudioManager.STREAM_VOICE_CALL
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            val current = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
            if (max > 0 && current * 10 < max * 4) {
                am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, (max * 6 + 9) / 10, 0)
            }
        } catch (_: Exception) {
            // Volume non modifiable sur ce téléphone : l'appel continue.
        }
    }

    private val audioHandler = Handler(Looper.getMainLooper())
    private var callAudioOn = false
    private var lastRoute: String? = null

    /**
     * Correctif du 18/11/2026 (haut-parleur faible) : la sortie choisie est imposée ici
     * aussi. Sur Android 12 et plus, le haut-parleur passe par setCommunicationDevice
     * (l'ancien réglage « speakerphone » est ignoré par certains téléphones). Android garde
     * un volume d'appel par sortie : celui de la sortie choisie est remonté s'il est bas
     * (haut-parleur : au moins 90 %, écouteur : 60 % s'il est sous 40 %). Appliqué deux
     * fois, car la bibliothèque d'appel change elle aussi la sortie juste après.
     */
    private fun setAudioRoute(route: String) {
        lastRoute = route
        if (!callAudioOn) return
        audioHandler.removeCallbacksAndMessages(null)
        applyAudioRoute(route)
        audioHandler.postDelayed({ applyAudioRoute(route) }, 350)
        audioHandler.postDelayed({ raiseCallVolume(route == "speaker") }, 700)
    }

    private fun applyAudioRoute(route: String) {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (am.mode != AudioManager.MODE_IN_COMMUNICATION) {
                am.mode = AudioManager.MODE_IN_COMMUNICATION
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val types = when (route) {
                    "speaker" -> setOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
                    "earpiece" -> setOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
                    "bluetooth" -> setOf(AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET)
                    else -> setOf(
                        AudioDeviceInfo.TYPE_WIRED_HEADSET,
                        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                        AudioDeviceInfo.TYPE_USB_HEADSET,
                    )
                }
                val device = am.availableCommunicationDevices.firstOrNull { it.type in types }
                if (device != null && am.communicationDevice?.id != device.id) {
                    am.setCommunicationDevice(device)
                }
            }
            if (route == "speaker" || route == "earpiece") {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = route == "speaker"
            }
        } catch (_: Exception) {
            // Sortie non modifiable sur ce téléphone : la bibliothèque d'appel s'en charge.
        }
    }

    /**
     * Lot 9.3c : état du son pendant l'appel, pour le journal technique (mode, sortie
     * réellement utilisée, volume d'appel). Aucune donnée personnelle.
     */
    private fun audioState(): Map<String, Any?>? {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val mode = when (am.mode) {
                AudioManager.MODE_IN_COMMUNICATION -> "communication"
                AudioManager.MODE_IN_CALL -> "appel"
                AudioManager.MODE_RINGTONE -> "sonnerie"
                AudioManager.MODE_NORMAL -> "normal"
                else -> "autre (${am.mode})"
            }
            @Suppress("DEPRECATION")
            val speakerOn = am.isSpeakerphoneOn
            val output = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                when (am.communicationDevice?.type) {
                    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "haut-parleur"
                    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "écouteur"
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET -> "bluetooth"
                    AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_USB_HEADSET -> "casque"
                    null -> "aucune"
                    else -> "autre"
                }
            } else {
                if (speakerOn) "haut-parleur" else "écouteur ou accessoire"
            }
            mapOf(
                "mode" to mode,
                "output" to output,
                "speakerphone" to speakerOn,
                "volume" to am.getStreamVolume(AudioManager.STREAM_VOICE_CALL),
                "max" to am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL),
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun raiseCallVolume(speaker: Boolean) {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            val current = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
            if (max <= 0) return
            val target = if (speaker) (max * 9 + 9) / 10 else (max * 6 + 9) / 10
            val low = if (speaker) current < target else current * 10 < max * 4
            if (low) am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, target, 0)
        } catch (_: Exception) {
            // Volume non modifiable sur ce téléphone : l'appel continue.
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
