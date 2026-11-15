import '../l10n/l10n.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/device_services.dart';
import 'messaging_providers.dart';
import 'providers.dart';

// ------------------------------------------------------------------------
// Réseau (DATA-006, DATA-007)
// ------------------------------------------------------------------------
final networkMonitorProvider = Provider<NetworkMonitor>((ref) => const AssumeOnlineMonitor());

/// Type de réseau actuel, puis ses changements.
final netKindProvider = StreamProvider<NetKind>((ref) async* {
  final monitor = ref.watch(networkMonitorProvider);
  yield await monitor.current();
  yield* monitor.changes();
});

// ------------------------------------------------------------------------
// Téléchargement des photos (DATA-001, DATA-003)
// ------------------------------------------------------------------------
enum PhotoAutoDownload {
  always('always'),
  wifi('wifi'),
  never('never');

  const PhotoAutoDownload(this.id);

  final String id;
  String get label => switch (this) {
    always => L.t.toujours,
    wifi => L.t.wiFiSeulement,
    never => L.t.jamaisToucherPourTelecharger,
  };

  static PhotoAutoDownload parse(String? v) =>
      values.firstWhere((x) => x.id == v, orElse: () => PhotoAutoDownload.always);
}

final photoAutoDownloadProvider =
    AsyncNotifierProvider<PhotoAutoDownloadController, PhotoAutoDownload>(
      PhotoAutoDownloadController.new,
    );

class PhotoAutoDownloadController extends AsyncNotifier<PhotoAutoDownload> {
  @override
  Future<PhotoAutoDownload> build() async =>
      PhotoAutoDownload.parse(await ref.read(localFlagsProvider).photoAutoDownload());

  Future<void> set(PhotoAutoDownload value) async {
    state = AsyncData(value);
    await ref.read(localFlagsProvider).setPhotoAutoDownload(value.id);
  }
}

/// Les photos reçues peuvent-elles se télécharger seules, maintenant ?
final photoAutoAllowedProvider = Provider<bool>((ref) {
  // Réglage pas encore lu : on attend (sinon une photo partirait avant de savoir).
  final mode = ref.watch(photoAutoDownloadProvider).value;
  if (mode == null) return false;
  return switch (mode) {
    PhotoAutoDownload.always => true,
    PhotoAutoDownload.never => false,
    PhotoAutoDownload.wifi => ref.watch(netKindProvider).value == NetKind.wifi,
  };
});

/// Photos que la personne a demandé à télécharger (clé du média).
final photoRequestsProvider = NotifierProvider<PhotoRequests, Set<String>>(PhotoRequests.new);

class PhotoRequests extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void request(String key) => state = {...state, key};
}

/// Photo déjà sur le téléphone (sans téléchargement), ou null.
final photoLocalProvider = FutureProvider.autoDispose.family<Uint8List?, PhotoRef>(
  (ref, photo) => ref.read(localCacheProvider).readMedia(photo.key),
);

// ------------------------------------------------------------------------
// Données consommées par les médias (DATA-009)
// ------------------------------------------------------------------------
final usageClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class DataUsage {
  const DataUsage(this.raw, this.month, this.previousMonth);

  final Map<String, int> raw;
  final String month;
  final String previousMonth;

  int received(String m) => raw['$m:in'] ?? 0;
  int sent(String m) => raw['$m:out'] ?? 0;
}

String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

final dataUsageProvider = AsyncNotifierProvider<DataUsageController, DataUsage>(
  DataUsageController.new,
);

class DataUsageController extends AsyncNotifier<DataUsage> {
  Timer? _save;

  DataUsage _wrap(Map<String, int> raw) {
    final now = ref.read(usageClockProvider)();
    return DataUsage(raw, monthKey(now), monthKey(DateTime(now.year, now.month - 1)));
  }

  @override
  Future<DataUsage> build() async {
    ref.onDispose(() => _save?.cancel());
    return _wrap(await ref.read(localFlagsProvider).dataUsage());
  }

  /// Compte des octets de médias reçus et/ou envoyés (texte non compté : négligeable).
  Future<void> add({int received = 0, int sent = 0}) async {
    if (received <= 0 && sent <= 0) return;
    final current = state.value ?? await future;
    final m = monthKey(ref.read(usageClockProvider)());
    final raw = Map<String, int>.of(current.raw);
    if (received > 0) raw['$m:in'] = (raw['$m:in'] ?? 0) + received;
    if (sent > 0) raw['$m:out'] = (raw['$m:out'] ?? 0) + sent;
    // Seuls le mois en cours et le précédent sont gardés.
    final keep = {current.month, current.previousMonth, m};
    raw.removeWhere((k, _) => !keep.contains(k.split(':').first));
    state = AsyncData(_wrap(raw));
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), () {
      unawaited(ref.read(localFlagsProvider).saveDataUsage(raw));
    });
  }

  Future<void> reset() async {
    _save?.cancel();
    state = AsyncData(_wrap({}));
    await ref.read(localFlagsProvider).saveDataUsage({});
  }
}

/// Compte sans jamais faire échouer l'opération principale.
void countData(Ref ref, {int received = 0, int sent = 0}) {
  try {
    unawaited(ref.read(dataUsageProvider.notifier).add(received: received, sent: sent));
  } on Object {
    // Compteur indicatif seulement.
  }
}

/// Même chose depuis un widget.
void countDataW(WidgetRef ref, {int received = 0, int sent = 0}) {
  try {
    unawaited(ref.read(dataUsageProvider.notifier).add(received: received, sent: sent));
  } on Object {
    // Compteur indicatif seulement.
  }
}

/// « 1,2 Mo », « 350 Ko ».
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return L.t.bytesKo((bytes / 1024).round());
  final mb = bytes / (1024 * 1024);
  final text = mb < 10 ? mb.toStringAsFixed(1) : mb.round().toString();
  return L.t.sizeMo(text.replaceAll('.', ','));
}
