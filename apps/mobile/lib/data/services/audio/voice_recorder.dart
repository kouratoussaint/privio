import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/util/ids.dart';

enum MicPermission { granted, denied, permanentlyDenied }

/// Enregistrement d'un message vocal (AAC dans un conteneur MP4, mono).
abstract interface class VoiceRecorder {
  /// Demande l'accès au micro si nécessaire (jamais bloquant pour le reste de l'app).
  Future<MicPermission> ensurePermission();

  Future<void> start();

  /// Arrête et renvoie le son ; le fichier temporaire est effacé aussitôt.
  Future<Uint8List?> stop();

  /// Abandonne l'enregistrement (rien n'est conservé).
  Future<void> cancel();

  Future<void> dispose();
}

/// Ouvre le réglage Android de l'application (micro refusé définitivement).
Future<void> openMicrophoneSettings() => openAppSettings();

/// Implémentation Android (paquet `record`). Le son passe par un fichier temporaire
/// privé de l'application, lu puis effacé dès l'arrêt : il n'est conservé ensuite que
/// chiffré (file d'envoi, coffre local).
class DeviceVoiceRecorder implements VoiceRecorder {
  DeviceVoiceRecorder() : _recorder = AudioRecorder();

  static const config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 32000,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
  );

  final AudioRecorder _recorder;
  String? _path;

  @override
  Future<MicPermission> ensurePermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return MicPermission.granted;
    if (status.isPermanentlyDenied) return MicPermission.permanentlyDenied;
    status = await Permission.microphone.request();
    if (status.isGranted) return MicPermission.granted;
    return status.isPermanentlyDenied ? MicPermission.permanentlyDenied : MicPermission.denied;
  }

  @override
  Future<void> start() async {
    try {
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/privio_rec_${uuidV4()}.m4a';
      await _recorder.start(config, path: _path!);
    } on Object {
      await _deleteFile();
      throw const AppFailure(FailureCode.microphoneUnavailable);
    }
  }

  @override
  Future<Uint8List?> stop() async {
    try {
      final path = await _recorder.stop() ?? _path;
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on Object {
      return null;
    } finally {
      await _deleteFile();
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } on Object {
      // déjà arrêté
    } finally {
      await _deleteFile();
    }
  }

  Future<void> _deleteFile() async {
    final path = _path;
    _path = null;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
