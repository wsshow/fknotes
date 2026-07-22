import 'package:flutter/material.dart';

import 'note_share.dart';

/// Geometry shared by pagination and rendering for every share-card theme.
///
/// Keeping these values in one place prevents a visually rich theme from
/// drifting away from the layout engine's capacity calculation.
class NoteShareTemplateMetrics {
  final double paperWidthFactor;
  final double paperHeightFactor;
  final double portraitHorizontalPadding;
  final double portraitVerticalPadding;
  final double landscapeHorizontalPadding;
  final double landscapeVerticalPadding;
  final double portraitTitleSize;
  final double landscapeTitleSize;
  final double titleHeight;
  final FontWeight titleWeight;
  final String? titleFontFamily;
  final double titleLetterSpacing;
  final TextAlign titleAlign;
  final double portraitTitleTopGap;
  final double portraitTitleBottomGap;
  final double landscapeTitleTopGap;
  final double landscapeTitleBottomGap;

  const NoteShareTemplateMetrics({
    required this.paperWidthFactor,
    required this.paperHeightFactor,
    required this.portraitHorizontalPadding,
    required this.portraitVerticalPadding,
    required this.landscapeHorizontalPadding,
    required this.landscapeVerticalPadding,
    required this.portraitTitleSize,
    this.landscapeTitleSize = 20,
    this.titleHeight = 1.2,
    this.titleWeight = FontWeight.w700,
    this.titleFontFamily,
    this.titleLetterSpacing = 0,
    this.titleAlign = TextAlign.start,
    this.portraitTitleTopGap = 10,
    this.portraitTitleBottomGap = 10,
    this.landscapeTitleTopGap = 6,
    this.landscapeTitleBottomGap = 6,
  });

  double horizontalPadding(bool landscape) =>
      landscape ? landscapeHorizontalPadding : portraitHorizontalPadding;

  double verticalPadding(bool landscape) =>
      landscape ? landscapeVerticalPadding : portraitVerticalPadding;

  double titleTopGap(bool landscape) =>
      landscape ? landscapeTitleTopGap : portraitTitleTopGap;

  double titleBottomGap(bool landscape) =>
      landscape ? landscapeTitleBottomGap : portraitTitleBottomGap;

  TextStyle titleStyle(bool landscape, {Color? color}) => TextStyle(
    color: color,
    fontFamily: titleFontFamily,
    fontSize: landscape ? landscapeTitleSize : portraitTitleSize,
    height: titleHeight,
    fontWeight: titleWeight,
    letterSpacing: titleLetterSpacing,
  );

  static NoteShareTemplateMetrics of(NoteShareTemplateId template) =>
      switch (template) {
        NoteShareTemplateId.letter => const NoteShareTemplateMetrics(
          paperWidthFactor: 1,
          paperHeightFactor: 1,
          portraitHorizontalPadding: 32,
          portraitVerticalPadding: 32,
          landscapeHorizontalPadding: 30,
          landscapeVerticalPadding: 22,
          portraitTitleSize: 25,
          titleFontFamily: 'serif',
        ),
        NoteShareTemplateId.plain => const NoteShareTemplateMetrics(
          paperWidthFactor: .92,
          paperHeightFactor: .9,
          portraitHorizontalPadding: 23,
          portraitVerticalPadding: 24,
          landscapeHorizontalPadding: 18,
          landscapeVerticalPadding: 11,
          portraitTitleSize: 25,
          titleFontFamily: 'serif',
        ),
        NoteShareTemplateId.night => const NoteShareTemplateMetrics(
          paperWidthFactor: .9,
          paperHeightFactor: .9,
          portraitHorizontalPadding: 26,
          portraitVerticalPadding: 26,
          landscapeHorizontalPadding: 20,
          landscapeVerticalPadding: 16,
          portraitTitleSize: 25,
          titleFontFamily: 'serif',
        ),
        NoteShareTemplateId.editorial => const NoteShareTemplateMetrics(
          paperWidthFactor: .94,
          paperHeightFactor: .94,
          portraitHorizontalPadding: 30,
          portraitVerticalPadding: 30,
          landscapeHorizontalPadding: 25,
          landscapeVerticalPadding: 16,
          portraitTitleSize: 28,
          landscapeTitleSize: 21,
          titleHeight: 1.08,
          titleWeight: FontWeight.w800,
          titleLetterSpacing: -.45,
          portraitTitleBottomGap: 15,
        ),
        NoteShareTemplateId.newspaper => const NoteShareTemplateMetrics(
          paperWidthFactor: .95,
          paperHeightFactor: .94,
          portraitHorizontalPadding: 27,
          portraitVerticalPadding: 25,
          landscapeHorizontalPadding: 23,
          landscapeVerticalPadding: 14,
          portraitTitleSize: 27,
          landscapeTitleSize: 21,
          titleHeight: 1.12,
          titleFontFamily: 'serif',
          titleAlign: TextAlign.center,
          portraitTitleTopGap: 8,
          portraitTitleBottomGap: 15,
        ),
        NoteShareTemplateId.manuscript => const NoteShareTemplateMetrics(
          paperWidthFactor: 1,
          paperHeightFactor: 1,
          portraitHorizontalPadding: 38,
          portraitVerticalPadding: 31,
          landscapeHorizontalPadding: 34,
          landscapeVerticalPadding: 20,
          portraitTitleSize: 24,
          titleFontFamily: 'serif',
          portraitTitleBottomGap: 14,
        ),
        NoteShareTemplateId.botanical => const NoteShareTemplateMetrics(
          paperWidthFactor: .94,
          paperHeightFactor: .94,
          portraitHorizontalPadding: 29,
          portraitVerticalPadding: 29,
          landscapeHorizontalPadding: 24,
          landscapeVerticalPadding: 16,
          portraitTitleSize: 25,
          titleFontFamily: 'serif',
          titleWeight: FontWeight.w600,
          portraitTitleBottomGap: 14,
        ),
        NoteShareTemplateId.blueprint => const NoteShareTemplateMetrics(
          paperWidthFactor: .94,
          paperHeightFactor: .92,
          portraitHorizontalPadding: 27,
          portraitVerticalPadding: 26,
          landscapeHorizontalPadding: 23,
          landscapeVerticalPadding: 14,
          portraitTitleSize: 22,
          landscapeTitleSize: 18,
          titleHeight: 1.18,
          titleFontFamily: 'monospace',
          titleWeight: FontWeight.w700,
          titleLetterSpacing: .35,
          portraitTitleBottomGap: 14,
        ),
        NoteShareTemplateId.amber => const NoteShareTemplateMetrics(
          paperWidthFactor: .92,
          paperHeightFactor: .92,
          portraitHorizontalPadding: 28,
          portraitVerticalPadding: 28,
          landscapeHorizontalPadding: 24,
          landscapeVerticalPadding: 16,
          portraitTitleSize: 27,
          landscapeTitleSize: 21,
          titleFontFamily: 'serif',
          titleAlign: TextAlign.center,
          portraitTitleBottomGap: 15,
        ),
        NoteShareTemplateId.film => const NoteShareTemplateMetrics(
          paperWidthFactor: .94,
          paperHeightFactor: .94,
          portraitHorizontalPadding: 35,
          portraitVerticalPadding: 28,
          landscapeHorizontalPadding: 31,
          landscapeVerticalPadding: 16,
          portraitTitleSize: 26,
          landscapeTitleSize: 20,
          titleHeight: 1.1,
          titleWeight: FontWeight.w800,
          titleLetterSpacing: -.25,
          portraitTitleBottomGap: 15,
        ),
        NoteShareTemplateId.postcard => const NoteShareTemplateMetrics(
          paperWidthFactor: .94,
          paperHeightFactor: .92,
          portraitHorizontalPadding: 31,
          portraitVerticalPadding: 29,
          landscapeHorizontalPadding: 27,
          landscapeVerticalPadding: 17,
          portraitTitleSize: 25,
          titleFontFamily: 'serif',
          titleWeight: FontWeight.w600,
          portraitTitleBottomGap: 14,
        ),
        NoteShareTemplateId.gallery => const NoteShareTemplateMetrics(
          paperWidthFactor: .9,
          paperHeightFactor: .92,
          portraitHorizontalPadding: 31,
          portraitVerticalPadding: 31,
          landscapeHorizontalPadding: 27,
          landscapeVerticalPadding: 17,
          portraitTitleSize: 29,
          landscapeTitleSize: 22,
          titleHeight: 1.05,
          titleWeight: FontWeight.w300,
          titleLetterSpacing: -.5,
          portraitTitleBottomGap: 18,
        ),
        NoteShareTemplateId.neon => const NoteShareTemplateMetrics(
          paperWidthFactor: .92,
          paperHeightFactor: .92,
          portraitHorizontalPadding: 28,
          portraitVerticalPadding: 28,
          landscapeHorizontalPadding: 24,
          landscapeVerticalPadding: 16,
          portraitTitleSize: 26,
          landscapeTitleSize: 20,
          titleHeight: 1.08,
          titleWeight: FontWeight.w800,
          titleLetterSpacing: -.3,
          portraitTitleBottomGap: 16,
        ),
        NoteShareTemplateId.tide => const NoteShareTemplateMetrics(
          paperWidthFactor: .94,
          paperHeightFactor: .94,
          portraitHorizontalPadding: 29,
          portraitVerticalPadding: 29,
          landscapeHorizontalPadding: 25,
          landscapeVerticalPadding: 16,
          portraitTitleSize: 25,
          titleFontFamily: 'serif',
          titleWeight: FontWeight.w600,
          portraitTitleBottomGap: 14,
        ),
        NoteShareTemplateId.vermilion => const NoteShareTemplateMetrics(
          paperWidthFactor: 1,
          paperHeightFactor: 1,
          portraitHorizontalPadding: 35,
          portraitVerticalPadding: 31,
          landscapeHorizontalPadding: 31,
          landscapeVerticalPadding: 20,
          portraitTitleSize: 26,
          titleFontFamily: 'serif',
          titleWeight: FontWeight.w600,
          portraitTitleBottomGap: 15,
        ),
      };
}
