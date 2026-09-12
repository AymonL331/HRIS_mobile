import 'package:flutter/material.dart';

import '../tokens.dart';

enum BrandMarkSize { bar, auth }

/// The web brand block (Sidebar.module.css .brand): a primary dot and the
/// "HRIS" wordmark, semibold and letter-spaced. [BrandMarkSize.bar] is the
/// top-bar size; [BrandMarkSize.auth] the larger, centred version the login
/// and splash use. Renders the word exactly once.
class BrandMark extends StatelessWidget {
  final BrandMarkSize size;

  const BrandMark({super.key, this.size = BrandMarkSize.bar});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final auth = size == BrandMarkSize.auth;
    final dot = auth ? 14.0 : HrisSize.brandDot;
    final fontSize = auth ? HrisType.xl : HrisType.lg;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: auth ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
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
