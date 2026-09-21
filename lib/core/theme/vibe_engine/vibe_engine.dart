import 'package:flutter/material.dart';

/// Layer B : presets visuels appliqués par playlist, indépendants du thème global.
/// Les noms correspondent exactement aux valeurs stockées en base (`playlists.vibe_style`).
/// `custom` délègue son rendu aux champs `bgColors` / `customBackgroundImagePath`
/// de la playlist plutôt qu'à une palette fixe — voir [PlaylistVibeResolver].
enum VibePreset { minimal, neon, glassmorphism, retro, organic, oled, custom }

class VibeTheme extends ThemeExtension<VibeTheme> {
  const VibeTheme({required this.preset, required this.gradientColors, required this.accentColor});

  final VibePreset preset;
  final List<Color> gradientColors;
  final Color accentColor;

  @override
  VibeTheme copyWith({VibePreset? preset, List<Color>? gradientColors, Color? accentColor}) {
    return VibeTheme(
      preset: preset ?? this.preset,
      gradientColors: gradientColors ?? this.gradientColors,
      accentColor: accentColor ?? this.accentColor,
    );
  }

  @override
  VibeTheme lerp(ThemeExtension<VibeTheme>? other, double t) {
    if (other is! VibeTheme) return this;
    return t < 0.5 ? this : other;
  }
}

/// Palette de chaque Vibe : dégradé de fond (Tab 2 pulsé au BPM) et couleur
/// d'accent des contrôles de lecture (Étape 5).
extension VibePresetStyle on VibePreset {
  List<Color> get gradientColors => switch (this) {
        VibePreset.minimal => const [Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
        // Cyberpunk/Blade Runner (Feuille de route Vibe v2) : nuit bleu-cyan
        // très sombre et moite en base (voir `_FluidPainter.paint`,
        // `colors.first` remplit tout le canvas) avec des éclats néon
        // magenta/rose et cyan fluo qui dérivent par-dessus.
        VibePreset.neon => const [Color(0xFF050D1A), Color(0xFFFF007F), Color(0xFF00F3FF)],
        // Verre teinté plutôt que blanc quasi-transparent : l'app n'a pas de
        // flou d'arrière-plan (BackdropFilter) pour donner du relief à un
        // vrai glassmorphism, donc un dégradé presque invisible laissait les
        // contrôles (accentColor blanc) illisibles quel que soit le fond
        // sous-jacent — bug réel repéré en testant la vibe en conditions
        // réelles sur le lecteur.
        VibePreset.glassmorphism => [Colors.indigo.shade200.withValues(alpha: 0.65), Colors.indigo.shade400.withValues(alpha: 0.45)],
        // Synthwave 80s (Feuille de route Vibe v2) : violet nuit profond en
        // haut vers magenta intense — le shader (styleIndex 1) peint
        // lui-même un dégradé vertical marqué + soleil strié + grille par-
        // dessus, ces deux couleurs ne servent donc plus qu'aux halos du
        // fond général (FluidBackground) hors zone du shader.
        VibePreset.retro => const [Color(0xFF12002B), Color(0xFFFF007F)],
        // Nature (Feuille de route Vibe v2) : vert forêt quasi noir plutôt
        // que le vert menthe clair précédent — les lianes/lucioles du shader
        // (styleIndex 2) doivent se détacher d'un fond sombre et mystérieux,
        // pas rivaliser avec lui.
        VibePreset.organic => const [Color(0xFF040B06), Color(0xFF15311F)],
        VibePreset.oled => const [Colors.black, Colors.black],
        // Repli tant que la playlist n'a pas encore de couleurs personnalisées
        // enregistrées (juste après le passage sur "Personnalisé").
        VibePreset.custom => const [Color(0xFF3A3A3A), Color(0xFF1A1A1A)],
      };

  Color get accentColor => switch (this) {
        VibePreset.minimal => Colors.black87,
        VibePreset.neon => const Color(0xFF00F3FF),
        VibePreset.glassmorphism => Colors.black87,
        // Doré/orangé issu du soleil couchant plutôt que le magenta de la
        // grille : les boutons/contrôles de lecture en magenta sur fond nuit
        // violette étaient illisibles (contraste insuffisant) — bug réel
        // signalé après avoir testé le preset sur le lecteur.
        VibePreset.retro => const Color(0xFFFFD700),
        VibePreset.organic => const Color(0xFF5CDB7A),
        VibePreset.oled => Colors.white,
        VibePreset.custom => Colors.white,
      };

  String get label => switch (this) {
        VibePreset.minimal => 'Minimal',
        VibePreset.neon => 'Neon',
        VibePreset.glassmorphism => 'Glassmorphism',
        VibePreset.retro => 'Retro',
        VibePreset.organic => 'Organic',
        VibePreset.oled => 'OLED',
        VibePreset.custom => 'Personnalisé',
      };
}

/// Style de particules du shader GLSL audio-réactif (Vibe Engine — voir
/// assets/shaders/vibe_particles.frag) : 0 = surcouche buée/pluie/grésillement
/// néon par-dessus la photo de skyline plein écran (`neon`, voir
/// FluidBackground/kCyberpunkCityImage), 1 = grille de perspective + soleil
/// strié synthwave (`retro`), 2 = lianes et lucioles (`organic`), 3 = champ
/// d'étoiles (`oled`, INCHANGÉ).
extension VibeParticleStyle on VibePreset {
  int? get particleStyleIndex => switch (this) {
        VibePreset.neon => 0,
        VibePreset.retro => 1,
        VibePreset.organic => 2,
        VibePreset.oled => 3,
        // Pas d'effet dédié : le dégradé de FluidBackground suffit, inutile
        // de payer le coût GPU du shader pour ces presets.
        VibePreset.minimal || VibePreset.glassmorphism || VibePreset.custom => null,
      };
}

/// Effet visuel du fond animé pour `VibePreset.custom` (Vibe Creator, Section
/// 4.2) — voir `FluidBackground`/`_FluidPainter` pour le rendu de chacun :
///  - [fluid] : rendu historique (halos flous qui dérivent), aussi utilisé
///    tel quel par tous les presets figés (`minimal`, `neon`, ...) qui
///    n'exposent pas ce choix.
///  - [animatedGradient] : dégradé plein écran dont l'angle tourne en continu,
///    sans les halos flous du mode Fluide.
///  - [radiation] : rayons pulsés depuis le centre au rythme du BPM.
enum VibeCustomEffect { fluid, animatedGradient, radiation }

/// Rendu effectif d'une Vibe : pour les presets fixes, dérivé de [VibePresetStyle] ;
/// pour `VibePreset.custom`, dérivé des champs propres à la playlist
/// (`bgColors`, `customBackgroundImagePath`, `customEffect`) plutôt que d'une
/// palette statique.
class VibeVisual {
  const VibeVisual({
    required this.gradientColors,
    required this.accentColor,
    this.backgroundImagePath,
    this.preset,
    this.effect = VibeCustomEffect.fluid,
    this.customBackgroundVideoPath,
  });

  final List<Color> gradientColors;
  final Color accentColor;
  final String? backgroundImagePath;
  // Preset d'origine — `null` pour le repli neutre (aucune playlist active).
  // Alimente le choix du style de particules (shader) et du profil haptique
  // (VibeHapticService), qui ont besoin du preset discret, pas seulement des
  // couleurs dérivées.
  final VibePreset? preset;
  // Choix propre à `VibePreset.custom` (Section 4.2) — [VibeCustomEffect.fluid]
  // pour tous les autres presets, qui n'exposent pas ce réglage.
  final VibeCustomEffect effect;
  // Vidéo de fond personnalisée (Section 4.3, `VibePreset.custom` uniquement)
  // — quand non nulle, remplace entièrement le rendu shader/dégradé/[effect]
  // du Master Player (voir MasterPlayerScreen), jamais superposée à celui-ci.
  final String? customBackgroundVideoPath;
}
