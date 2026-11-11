package com.privio.app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

/**
 * SEC-005 : FLAG_SECURE appliqué à toute l'application dès la création de la fenêtre.
 * Bloque captures et enregistrements d'écran système, et masque l'aperçu dans les
 * applications récentes. Limite connue : inefficace contre un appareil rooté/compromis
 * ou une caméra externe (aucune promesse absolue n'est faite à l'utilisateur).
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }
}
