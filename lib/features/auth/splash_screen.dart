import 'package:flutter/material.dart';

import '../../shared/tokens.dart';
import '../../shared/widgets/brand_mark.dart';

/// Shown while the stored session is being validated on a cold start: the
/// brand mark on the page background, the same as the native splash.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            BrandMark(size: BrandMarkSize.auth),
            SizedBox(height: HrisSpace.s5),
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}
