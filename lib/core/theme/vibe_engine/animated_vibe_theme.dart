import 'package:flutter/material.dart';

import 'vibe_engine.dart';

/// Interpolation douce entre deux [VibeVisual] (800ms, `Curves.easeInOutCubic`)
/// — élimine tout changement de couleur brutal lors d'un changement de piste,
/// de playlist ou de preset Vibe. Les descendants consomment le [VibeVisual]
/// interpolé via [builder], jamais `vibe` directement : `FluidBackground`,
/// les boutons/slider du Player reçoivent ainsi une palette qui glisse en
/// continu plutôt que de sauter.
///
/// `ImplicitlyAnimatedWidget` (comme `AnimatedContainer`) plutôt qu'un
/// `TweenAnimationBuilder` manuel : la transition redémarre proprement à
/// chaque nouveau `vibe`, y compris si une transition précédente est encore
/// en cours (changement de piste rapide).
class AnimatedVibeTheme extends ImplicitlyAnimatedWidget {
  const AnimatedVibeTheme({super.key, required this.vibe, required this.builder, this.child})
      : super(duration: const Duration(milliseconds: 800), curve: Curves.easeInOutCubic);

  final VibeVisual vibe;
  final Widget Function(BuildContext context, VibeVisual vibe, Widget? child) builder;
  final Widget? child;

  @override
  AnimatedWidgetBaseState<AnimatedVibeTheme> createState() => _AnimatedVibeThemeState();
}

class _AnimatedVibeThemeState extends AnimatedWidgetBaseState<AnimatedVibeTheme> {
  _VibeVisualTween? _vibeTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _vibeTween = visitor(
      _vibeTween,
      widget.vibe,
      (dynamic value) => _VibeVisualTween(begin: value as VibeVisual),
    ) as _VibeVisualTween?;
  }

  @override
  Widget build(BuildContext context) {
    final VibeVisual animatedVibe = _vibeTween?.evaluate(animation) ?? widget.vibe;
    return widget.builder(context, animatedVibe, widget.child);
  }
}

class _VibeVisualTween extends Tween<VibeVisual> {
  _VibeVisualTween({super.begin});

  @override
  VibeVisual lerp(double t) {
    final VibeVisual a = begin!;
    final VibeVisual b = end!;
    final List<Color> aColors = normalizeVibeColors(a.gradientColors);
    final List<Color> bColors = normalizeVibeColors(b.gradientColors);

    return VibeVisual(
      gradientColors: [for (int i = 0; i < aColors.length; i++) Color.lerp(aColors[i], bColors[i], t)!],
      accentColor: Color.lerp(a.accentColor, b.accentColor, t)!,
      // Pas d'interpolation qui ait du sens pour un chemin de fichier ou un
      // enum — bascule à mi-transition plutôt que de figer sur l'ancienne
      // valeur jusqu'à la fin.
      backgroundImagePath: t < 0.5 ? a.backgroundImagePath : b.backgroundImagePath,
      preset: t < 0.5 ? a.preset : b.preset,
      effect: t < 0.5 ? a.effect : b.effect,
      // `customBackgroundVideoPath` OUBLIÉ ici auparavant : retombait donc à
      // `null` (défaut du constructeur) sur CHAQUE frame interpolée, tant que
      // 0 < t < 1 — MasterPlayerScreen bascule sur cette seule valeur entre
      // `VibeVideoBackground` et `FluidBackground` (deux sous-arbres de
      // widgets structurellement différents), donc un changement de piste
      // vers/depuis une Vibe avec vidéo de fond faisait flapper les deux
      // pendant tout le fondu (800ms) — plantage réel reproduit en rafale de
      // "suivant" rapprochés : "'renderObject.child == child': is not true."
      customBackgroundVideoPath: t < 0.5 ? a.customBackgroundVideoPath : b.customBackgroundVideoPath,
    );
  }
}

/// Toujours 3 couleurs, pour que l'interpolation pairwise reste valide même
/// entre un preset à 2 couleurs et une palette de pochette qui peut en avoir 3
/// (voir FluidBackground) — dupliquer la dernière couleur plutôt que de
/// planter sur une liste plus courte.
List<Color> normalizeVibeColors(List<Color> colors) {
  if (colors.isEmpty) return const [Colors.black, Colors.black, Colors.black];
  if (colors.length >= 3) return colors.sublist(0, 3);
  return [...colors, ...List.filled(3 - colors.length, colors.last)];
}
