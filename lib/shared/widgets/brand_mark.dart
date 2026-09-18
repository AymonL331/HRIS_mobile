import 'package:flutter/material.dart';

import '../tokens.dart';

enum BrandMarkSize { bar, auth }

/// The HRIS brand block, as the website draws it: the mark, then the "HRIS"
/// wordmark to its right, semibold and letter-spaced. [BrandMarkSize.bar] is the
/// top-bar / sidebar size; [BrandMarkSize.auth] the larger, centred version the
/// login and splash use. Renders the word exactly once.
///
/// Two artworks, like the website (BrandLogo.jsx): the dark one's glow only
/// reads on a dark surface, so the mark follows the theme the app is drawn in.
class BrandMark extends StatelessWidget {
  final BrandMarkSize size;

  const BrandMark({super.key, this.size = BrandMarkSize.bar});

  static const lightAsset = 'assets/brand/hris-icon-light.png';
  static const darkAsset = 'assets/brand/hris-icon-dark.png';

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final auth = size == BrandMarkSize.auth;
    final mark = auth ? HrisSize.brandMarkAuth : HrisSize.brandMark;
    final fontSize = auth ? HrisType.xl : HrisType.lg;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: auth ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Image.asset(
          dark ? darkAsset : lightAsset,
          width: mark,
          height: mark,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
        SizedBox(width: auth ? HrisSpace.s3 : HrisSpace.s2),
        Text(
          'HRIS',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: HrisType.semibold,
            height: 1.2,
            color: t.text,
            letterSpacing: fontSize * (auth ? 0.04 : 0.05),
          ),
        ),
      ],
    );
  }
}
