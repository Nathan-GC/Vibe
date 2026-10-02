import 'package:workmanager/workmanager.dart';

import '../storage/database/app_database.dart';
import 'local_notification_service.dart';
import 'orphan_detector_service.dart';
import 'purge_check_runner.dart';
import 'purge_check_storage.dart';

const String orphanPurgeTaskName = 'orphan_purge_daily_check';

/// Exécutée par WorkManager dans un **isolate séparé**, sans accès à l'arbre
/// Riverpod de l'app ni à la connexion DB déjà ouverte — reconstruit donc ses
/// propres instances. Le contrôle "30 jours écoulés ?" est fait à l'intérieur
/// de PurgeCheckRunner ; cette tâche est planifiée à une fréquence *quotidienne*
/// (le minimum toléré par WorkManager pour un travail fiable) mais ne scanne
/// et ne notifie réellement qu'une fois par mois.
@pragma('vm:entry-point')
void purgeCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final AppDatabase db = AppDatabase();
    final LocalNotificationService notifications = LocalNotificationService();
    await notifications.initialize();

    final PurgeCheckRunner runner = PurgeCheckRunner(PurgeCheckStorage(), OrphanDetectorService(db), notifications);
    await runner.runIfDue(inBackground: true);

    await db.close();
    return true;
  });
}

/// À initialiser une fois au démarrage (voir app/bootstrap.dart). Nécessite
/// le wiring natif standard de `workmanager` (AndroidManifest.xml n'a rien à
/// ajouter sur Android ; iOS requiert l'enregistrement du background task
/// identifier dans Info.plist + AppDelegate) — non générable ici sans SDK
/// Flutter installé, voir `flutter create .`.
class PurgeBackgroundScheduler {
  Future<void> initialize() async {
    await Workmanager().initialize(purgeCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      orphanPurgeTaskName,
      orphanPurgeTaskName,
      frequency: const Duration(days: 1),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}
