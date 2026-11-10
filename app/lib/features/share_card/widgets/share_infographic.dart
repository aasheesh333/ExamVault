import 'package:flutter/material.dart';

import '../../../core/theme/theme_tokens.dart';

/// Sentinel for `copyWith` — see [ShareCardData.copyWith].
const Object _clear = Object();

/// Everything the viral card renders.
@immutable
class ShareCardData {
  const ShareCardData({
    required this.examName,
    required this.headline,
    required this.subline,
    required this.dateLine,
    required this.rollNumber,
    required this.selected,
    required this.shareUrl,
    this.officialUrl,
    this.cutoffs,
    this.pdfSizeLabel,
  });

  final String examName;
  final String headline;
  final String subline;
  final String dateLine;
  final String rollNumber;
  final bool selected;

  /// Null when no public web base is configured — the card then shows no URL
  /// rather than a dead link to a domain we do not own.
  final String? shareUrl;

  /// The commission's own document/page for this result.
  ///
  /// Used when there is no app-owned share URL: copying *this* is strictly
  /// better than a disabled button, because the recipient can open it and the
  /// link is to the authority that published the result.
  final String? officialUrl;

  /// Whichever link we can honestly offer, if any.
  String? get link => shareUrl ?? officialUrl;

  /// True when the only link is the commission's, so the UI can label it
  /// correctly instead of implying an app page.
  bool get linkIsOfficial => shareUrl == null && officialUrl != null;

  /// Only rendered when the publisher actually released cut-offs. Showing a
  /// made-up cut-off on a card that gets forwarded 10 000 times is exactly the
  /// kind of misinformation this product cannot afford.
  final Map<String, String>? cutoffs;

  final String? pdfSizeLabel;

  /// Used when the user turns off "Show my roll number": the card keeps the
  /// result, the subline and the link, and drops the personal number.
  ShareCardData copyWith({
    String? rollNumber,
    bool? selected,
    // `_clear` rather than `null`, so "no app URL" is expressible: a plain
    // nullable parameter cannot distinguish "leave alone" from "set to null".
    Object? shareUrl = _clear,
  }) => ShareCardData(
    examName: examName,
    headline: headline,
    subline: subline,
    dateLine: dateLine,
    rollNumber: rollNumber ?? this.rollNumber,
    selected: selected ?? this.selected,
    shareUrl: identical(shareUrl, _clear) ? this.shareUrl : shareUrl as String?,
    officialUrl: officialUrl,
    cutoffs: cutoffs,
    pdfSizeLabel: pdfSizeLabel,
  );
}

/// The shareable infographic.
///
/// Hard-coded light-on-dark contrast on purpose: it is *exported as a PNG*, so it
/// must not inherit the app theme. A dark card disappears in WhatsApp's light
/// chat list; an alabaster card with black type survives every client.
class ShareInfographic extends StatelessWidget {
  const ShareInfographic({super.key, required this.data});

  final ShareCardData data;

  static const _ink = Color(0xFF0B0F19);
  static const _paper = Color(0xFFF8FAFC);
  static const _blue = Color(0xFF2563EB);
  static const _muted = Color(0xFF475569);
  static const _faint = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 44,
            offset: const Offset(0, 22),
            spreadRadius: -16,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AlertStrip(dateLine: data.dateLine),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BrandRow(shareUrl: data.shareUrl),
                  const SizedBox(height: 14),
                  Text(
                    data.examName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: EvFont.mono,
                      fontFamilyFallback: EvFont.fallbackMono,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: _blue,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _Headline(headline: data.headline),
                  const SizedBox(height: 9),
                  Text(
                    data.subline,
                    maxLines: 2,
                    style: const TextStyle(
                      fontFamily: EvFont.ui,
                      fontFamilyFallback: EvFont.fallbackUi,
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 13),
                  if (data.cutoffs != null && data.cutoffs!.isNotEmpty)
                    _CutoffBlock(cutoffs: data.cutoffs!)
                  else if (data.rollNumber.isNotEmpty)
                    _RollBlock(data: data),
                  const SizedBox(height: 12),
                  _CtaBar(link: data.link),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text(
                      // Always-true claims only. "VERIFIED SOURCE" was printed
                      // unconditionally, which is a promise the app cannot keep
                      // for a card the user typed in themselves.
                      'FREE · NO ACCOUNT · CHECKED ON YOUR DEVICE',
                      style: TextStyle(
                        fontFamily: EvFont.mono,
                        fontFamilyFallback: EvFont.fallbackMono,
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.7,
                        color: _faint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertStrip extends StatelessWidget {
  const _AlertStrip({required this.dateLine});

  final String dateLine;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFF05252), Color(0xFFDC2626)],
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_active_rounded,
            size: 13,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'RESULT IS LIVE',
              style: TextStyle(
                fontFamily: EvFont.ui,
                fontFamilyFallback: EvFont.fallbackUi,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
                color: Colors.white,
              ),
            ),
          ),
          Text(
            dateLine,
            style: TextStyle(
              fontFamily: EvFont.mono,
              fontFamilyFallback: EvFont.fallbackMono,
              fontSize: 8,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.9,
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.shareUrl});

  /// Null when no public web base is configured — the card then shows no URL
  /// rather than a dead link to a domain we do not own.
  final String? shareUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
            ),
          ),
          child: const Icon(
            Icons.shield_outlined,
            size: 10,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'EXAMVAULT',
          style: TextStyle(
            fontFamily: EvFont.mono,
            fontFamilyFallback: EvFont.fallbackMono,
            fontSize: 8.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.9,
            color: ShareInfographic._faint,
          ),
        ),
        const Spacer(),
        if (shareUrl != null && shareUrl!.isNotEmpty)
          Flexible(
            child: Text(
              shareUrl!
                  .replaceFirst('https://', '')
                  .replaceFirst('http://', ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: EvFont.mono,
                fontFamilyFallback: EvFont.fallbackMono,
                fontSize: 8,
                color: ShareInfographic._faint,
                letterSpacing: 0.3,
              ),
            ),
          ),
      ],
    );
  }
}

/// "RESULT / IS LIVE" with the marker highlight behind the last word.
class _Headline extends StatelessWidget {
  const _Headline({required this.headline});

  final String headline;

  @override
  Widget build(BuildContext context) {
    // Split on the last space so the accent word is always the tail.
    final parts = headline.trim().split(RegExp(r'\s+'));
    final accent = parts.length > 1 ? parts.last : '';
    final lead = parts.length > 1
        ? parts.sublist(0, parts.length - 1).join(' ')
        : headline;

    // `height: 0.96` is a deliberate typographic choice — the lines should sit
    // tight. But it makes the line box shorter than the glyphs, and `Text`
    // defaults to `TextOverflow.clip`, which then slices the bottom off every
    // letter. `visible` is the fix; the surrounding padding still controls
    // spacing.
    const base = TextStyle(
      fontFamily: EvFont.ui,
      fontFamilyFallback: EvFont.fallbackUi,
      fontSize: 38,
      height: 0.96,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.9,
      color: ShareInfographic._ink,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(lead, maxLines: 2, overflow: TextOverflow.visible, style: base),
        if (accent.isNotEmpty)
          Stack(
            // The highlight bar is painted behind the word and the glyphs are
            // allowed outside their line box, so nothing here may clip.
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 4,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: ShareInfographic._blue.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(accent, overflow: TextOverflow.visible, style: base),
            ],
          ),
      ],
    );
  }
}

class _CutoffBlock extends StatelessWidget {
  const _CutoffBlock({required this.cutoffs});

  final Map<String, String> cutoffs;

  @override
  Widget build(BuildContext context) {
    final entries = cutoffs.entries.take(4).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 12),
      decoration: BoxDecoration(
        color: ShareInfographic._ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CUT-OFF',
            style: TextStyle(
              fontFamily: EvFont.mono,
              fontFamilyFallback: EvFont.fallbackMono,
              fontSize: 7,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.3,
              color: Color(0xFF8CA0BA),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final e in entries)
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        e.key,
                        style: const TextStyle(
                          fontFamily: EvFont.mono,
                          fontFamilyFallback: EvFont.fallbackMono,
                          fontSize: 7,
                          color: Color(0xFF7E90A8),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          e.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: EvFont.mono,
                            fontFamilyFallback: EvFont.fallbackMono,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF8FAFC),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Used when no cut-off has been published — shows the one fact we do have.
class _RollBlock extends StatelessWidget {
  const _RollBlock({required this.data});

  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: ShareInfographic._ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // "SELECTED" is only true of a final merit list. Most of what
                  // this app indexes is a shortlist for the next stage (UPSC's
                  // "qualified for the Personality Test"), so the card says what
                  // is actually established: the roll is in the published list.
                  data.selected ? 'YOUR ROLL · IN THE LIST' : 'YOUR ROLL',
                  style: const TextStyle(
                    fontFamily: EvFont.mono,
                    fontFamilyFallback: EvFont.fallbackMono,
                    fontSize: 7,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                    color: Color(0xFF8CA0BA),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.rollNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: EvFont.mono,
                    fontFamilyFallback: EvFont.fallbackMono,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: data.selected
                        ? const Color(0xFF6EE7B7)
                        : const Color(0xFFF8FAFC),
                  ),
                ),
              ],
            ),
          ),
          if (data.pdfSizeLabel != null)
            Text(
              data.pdfSizeLabel!,
              style: const TextStyle(
                fontFamily: EvFont.mono,
                fontFamilyFallback: EvFont.fallbackMono,
                fontSize: 9,
                color: Color(0xFF8CA0BA),
              ),
            ),
        ],
      ),
    );
  }
}

/// `https://a.b/c/d` -> `a.b`. Falls back to the trimmed string when the URL is
/// unparseable, so a malformed link is visible rather than silently blanked.
String _host(String url) {
  final uri = Uri.tryParse(url);
  if (uri != null && uri.host.isNotEmpty) return uri.host;
  return url.replaceFirst(RegExp(r'^https?://'), '');
}

class _CtaBar extends StatelessWidget {
  const _CtaBar({required this.link});

  /// Null when no link exists at all — the card then says so rather than printing
  /// a dead URL.
  final String? link;

  @override
  Widget build(BuildContext context) {
    // This is an exported PNG: nothing on it can be tapped. A button-shaped bar
    // reading "Check your roll number" is therefore a dead affordance the
    // recipient will try to press. It shows the destination instead, so a
    // screenshot still tells someone where to go.
    final target = link;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: ShareInfographic._blue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              // The host, not the whole URL: an official PDF path is 90
              // characters of hashes and dates, which truncated to noise on the
              // card. The full link still travels in the caption.
              target == null ? 'Ask in your study group' : _host(target),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: EvFont.mono,
                fontFamilyFallback: EvFont.fallbackMono,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: Colors.white,
              ),
            ),
          ),
          // A globe, not a QR glyph: there is no QR code on this card, and an
          // icon that promises a scanner is worse than no icon. The caption
          // carries the full tappable link.
          const Icon(Icons.language_rounded, size: 15, color: Colors.white),
        ],
      ),
    );
  }
}
