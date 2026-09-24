# Vibe Player

Lecteur de musique Android **local-first** développé en Flutter : bibliothèque
100 % locale (Drift/SQLite), modes visuels immersifs (« Vibes » : shaders GLSL,
nébuleuse, fonds vidéo) et interface pensée pour les dalles OLED.

Référence fonctionnelle et architecture détaillée :
[`documentation_master_vibe_player.md`](documentation_master_vibe_player.md).

---

## Passation — Release v1.0.0

| Élément | Valeur |
| :--- | :--- |
| Version (`pubspec.yaml`) | `1.0.0+2` |
| Commit de release | tag annoté `v1.0.0` (`git rev-parse v1.0.0`), sur la base `7dd7914` |
| `flutter analyze` | **0 issue** (0 erreur / 0 warning / 0 lint) |
| Tests (`flutter test --concurrency=1`) | **108 / 108 verts** |
| Formatage | `dart format .` appliqué — largeur 120 colonnes (`analysis_options.yaml`) |
| Binaire de référence | `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` |
| Autres binaires | `app-release.apk` (universel), `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk` |

Le hash du commit de release ne peut pas figurer dans ce fichier (il en fait
partie) : le tag `v1.0.0` le désigne sans ambiguïté.

### Branding Android

- Libellé : `android:label="Vibe"` (Manifest) ; titre de tâche `MaterialApp.title = 'Vibe'`.
- Icône adaptative `mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_round.xml` :
  fond vectoriel noir pur `#000000` plein cadre 108×108 dp, 5 barres néon `#6A0DAD`
  dans la zone de sécurité de 66 dp, calque `<monochrome>` pour les icônes à thème.
- ⚠️ Le dossier `android/` est **gitignoré** : Manifest, icônes et code natif n'apparaissent
  jamais dans `git status`. Les sauvegarder à part avant toute réinstallation du poste.

### Identifiants à ne jamais renommer

- Nom de base SQLite `playlist_app` (`AppDatabase._openConnection`) : le changer perdrait
  la bibliothèque existante des utilisateurs.
- Package Android `com.example.playlist_app` et canal de notification
  `com.example.playlist_app.channel.audio` : les changer casserait la mise à jour en place.
- Valeurs de `VibePreset` stockées en base (`oled` = « Space », `newOled` = « OLED ») :
  rétrocompatibilité des playlists existantes.

---

## Commandes

```bash
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter build apk --release --split-per-abi
```

`flutter test` **sans** `--concurrency=1` n'exécute silencieusement qu'un seul fichier
de test sur ce poste : toujours passer le flag pour obtenir la suite complète.

Codegen (Riverpod / Drift) après modification d'une classe annotée :

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## Conventions du projet

- **Qualité** : `flutter analyze` à 0 issue et suite de tests entièrement verte avant tout commit.
- **Gestes** : appui simple = action principale immédiate (lecture d'une playlist/artiste) ;
  appui long = vue détaillée (éditeur, fiche artiste, actions de morceau). Exception : listes
  réordonnables (file d'attente, éditeur), où l'appui long sert au glisser-déposer.
- **Mode Focus** : jamais déclenché sans interaction utilisateur sur le Lecteur ; annulé dès
  que le Lecteur n'est plus au premier plan (onglet, sous-page, arrière-plan) —
  voir `ShellRouteVisibility` et `_PlayerPageState`.
- **OLED** : les bords d'écran des Vibes sombres restent strictement `#000000`
  (nébuleuse Space bornée par une ellipse à 85 % de la distance aux bords).
- **Barre d'état** : icônes claires sur Vibe sombre, sombres sur Vibe claire
  (`AnnotatedRegion` du `MasterPlayerScreen`).
- **Logs** : aucun `print`/`log` dans `lib/` ; tout futur log de diagnostic doit être
  encapsulé dans `if (kDebugMode)`.

---

## Journal v1.0.0 (nettoyage de release)

- Barre d'état du Lecteur lisible sur les Vibes sombres/OLED (icônes blanches).
- Branding « Vibe » dans À propos et le titre de tâche Android.
- Nébuleuse Space : repli indigo sans pochette rehaussé (gain ×1,4, teintes de la charte
  conservées), bords toujours `#000000`.
- Calque `<monochrome>` réintégré à l'icône adaptative.
- Dépendances inutilisées retirées : `json_annotation`, `json_serializable`, `collection`,
  `cupertino_icons`, et la déclaration directe redondante de `sqlite3_flutter_libs`
  (toujours fournie par `drift_flutter`).
- `dart format .` appliqué à tout le projet (120 colonnes).

### Points ouverts (hors périmètre v1.0.0)

- Paquet transitif `js` signalé *discontinued* par `pub` (dépendance web indirecte, sans
  impact Android) ; 28 paquets ont des versions majeures plus récentes non adoptées.
- `riverpod_lint` est déclaré mais pas branché dans `analysis_options.yaml` (inactif).
- `google_fonts` (police Outfit) télécharge la police au premier lancement : à embarquer
  dans `assets/fonts/` pour une autonomie zéro-réseau stricte.
