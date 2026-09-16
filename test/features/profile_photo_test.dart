import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/core/http/api_exception.dart';
import 'package:hris_mobile/features/profile_photo/profile_photo_api.dart';
import 'package:hris_mobile/features/profile_photo/profile_photo_models.dart';
import 'package:hris_mobile/features/profile_photo/profile_photo_screen.dart';
import 'package:hris_mobile/core/auth/user.dart';
import 'package:hris_mobile/shared/theme.dart';
import 'package:hris_mobile/shared/widgets/user_avatar.dart';

// PROFILE PHOTO from the app (server migration 062). What matters: the photo only
// changes after HR approves (the screen never says otherwise), a rejection shows HR's
// reason, the camera is the only source, and a login without the grant is told why
// instead of being offered a button that would fail.

class FakeProfilePhotoApi implements ProfilePhotoApi {
  ProfilePhotoState current;
  final List<Uint8List> submits = [];
  ApiException? submitError;

  FakeProfilePhotoApi(this.current);

  @override
  Future<ProfilePhotoState> state() async => current;

  @override
  Future<ProfilePhotoState> submit(Uint8List jpeg) async {
    if (submitError != null) throw submitError!;
    submits.add(jpeg);
    current = ProfilePhotoState(phase: ProfilePhotoPhase.pending, submittedAt: DateTime.utc(2026, 9, 15, 9, 40));
    return current;
  }
}

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

Future<FakeProfilePhotoApi> mount(
  WidgetTester tester, {
  ProfilePhotoState state = ProfilePhotoState.empty,
  bool canSend = true,
  PhotoTaker? take,
}) async {
  final api = FakeProfilePhotoApi(state);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: Scaffold(
      body: ProfilePhotoScreen(
        api: api,
        baseUrl: 'https://hris.test',
        canSend: canSend,
        // Never a real image here: a 1x1 grey pixel is still a valid Image.memory.
        takePhotoOverride: take ?? () async => jpeg,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  test('state parses each phase, the reason, and treats a blank photo path as none', () {
    final s = ProfilePhotoState.fromJson({
      'state': 'rejected',
      'profile_image_url': '',
      'submitted_at': '2026-09-15T09:40:00.000Z',
      'reviewed_at': '2026-09-15T10:00:00.000Z',
      'reason': 'Face is too dark',
    });
    expect(s.phase, ProfilePhotoPhase.rejected);
    expect(s.profileImageUrl, isNull);
    expect(s.reason, 'Face is too dark');
    expect(ProfilePhotoState.fromJson({'state': 'cancelled'}).phase, ProfilePhotoPhase.none);
    expect(ProfilePhotoState.fromJson(null).phase, ProfilePhotoPhase.none);
  });

  test('only JPEG bytes are sent', () {
    expect(looksLikeJpeg(jpeg), isTrue);
    expect(looksLikeJpeg(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])), isFalse);
  });

  testWidgets('no photo yet: says so and offers the camera', (tester) async {
    await mount(tester);
    expect(find.text('No profile photo yet'), findsOneWidget);
    expect(find.text('Take a new photo'), findsOneWidget);
    expect(find.textContaining('HR checks the photo'), findsOneWidget);
  });

  testWidgets('take -> preview -> Send to HR: the photo is sent and the screen says it waits for HR', (tester) async {
    final api = await mount(tester);
    await tester.tap(find.text('Take a new photo'));
    await tester.pumpAndSettle();
    expect(find.text('Your new photo'), findsOneWidget);
    expect(find.text('Send to HR'), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
    expect(api.submits, isEmpty, reason: 'nothing is sent until the person confirms');

    await tester.tap(find.text('Send to HR'));
    await tester.pumpAndSettle();
    expect(api.submits.single, jpeg);
    expect(find.textContaining('waiting for HR to approve'), findsOneWidget);
    expect(find.textContaining('Your current photo stays until then'), findsOneWidget);
    expect(find.text('Take another photo'), findsOneWidget);
  });

  testWidgets('backing out of the camera changes nothing', (tester) async {
    final api = await mount(tester, take: () async => null);
    await tester.tap(find.text('Take a new photo'));
    await tester.pumpAndSettle();
    expect(find.text('Send to HR'), findsNothing);
    expect(api.submits, isEmpty);
  });

  testWidgets('a picture that is not a JPEG is refused on the phone', (tester) async {
    final api = await mount(tester, take: () async => Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0]));
    await tester.tap(find.text('Take a new photo'));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't send"), findsOneWidget);
    expect(find.text('Send to HR'), findsNothing);
    expect(api.submits, isEmpty);
  });

  testWidgets('camera permission refused: says so and offers Android settings', (tester) async {
    await mount(tester, take: () async => throw const CameraPermissionDenied());
    await tester.tap(find.text('Take a new photo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('camera is not allowed'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('a rejection shows HR\'s reason', (tester) async {
    await mount(
      tester,
      state: const ProfilePhotoState(phase: ProfilePhotoPhase.rejected, reason: 'Face is too dark'),
    );
    expect(find.textContaining('not approved'), findsOneWidget);
    expect(find.textContaining('Reason: Face is too dark'), findsOneWidget);
    expect(find.text('Take a new photo'), findsOneWidget);
  });

  testWidgets('without the grant: no camera button, and the reason is given', (tester) async {
    await mount(tester, canSend: false);
    expect(find.text('Take a new photo'), findsNothing);
    expect(find.textContaining('turned off for your account'), findsOneWidget);
  });

  // The photo is only worth approving if it then SHOWS. It reaches the app in the
  // session payload (`profile_image_url`), and the avatar in the top bar and the
  // drawer is where the user looks for it (2026-09-16: it drew the initial only).
  test('the session payload carries the profile photo; copyWith moves it to a new one', () {
    final u = User.fromJson({
      'id': 1, 'tenant_id': 1, 'employee_id': 2316, 'username': 'sofia', 'email': 's@x.test',
      'role_name': 'Employee', 'must_change_password': false, 'mobile_access_enabled': 1,
      'profile_image_url': '/api/uploads/employees/abc.jpg',
    });
    expect(u.profileImageUrl, '/api/uploads/employees/abc.jpg');
    expect(u.copyWith(profileImageUrl: '/api/uploads/employees/new.jpg').profileImageUrl, '/api/uploads/employees/new.jpg');
    // A login with no employee, or no photo yet: blank is the same as none.
    expect(User.fromJson({'id': 1, 'username': 'admin', 'profile_image_url': '  '}).profileImageUrl, isNull);
    expect(User.fromJson({'id': 1, 'username': 'admin'}).profileImageUrl, isNull);
  });

  testWidgets('the avatar draws the photo when there is one', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(
        body: UserAvatar('sofia', imageUrl: '/api/uploads/employees/abc.jpg', baseUrl: 'https://hris.test'),
      ),
    ));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the avatar falls back to the initial with no photo, and with no server to fetch it from', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(body: UserAvatar('sofia')),
    ));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('S'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(body: UserAvatar('sofia', imageUrl: '/api/uploads/employees/abc.jpg')),
    ));
    await tester.pump();
    expect(find.byType(Image), findsNothing, reason: 'a relative path is unusable without the environment');
    expect(find.text('S'), findsOneWidget);
  });

  testWidgets('the screen reports the photo it learned, so the avatars follow an approval', (tester) async {
    final seen = <String?>[];
    final api = FakeProfilePhotoApi(const ProfilePhotoState(
      phase: ProfilePhotoPhase.approved,
      profileImageUrl: '/api/uploads/employees/approved.jpg',
    ));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: ProfilePhotoScreen(
          api: api,
          baseUrl: 'https://hris.test',
          canSend: true,
          onPhotoChanged: seen.add,
          takePhotoOverride: () async => jpeg,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(seen, ['/api/uploads/employees/approved.jpg']);
  });

  testWidgets('the server refusing the grant (403) is explained, not shown raw', (tester) async {
    final api = await mount(tester);
    api.submitError = const ApiException(status: 403, message: 'You do not have permission to perform this action.');
    await tester.tap(find.text('Take a new photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to HR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('turned off for your account'), findsOneWidget);
    expect(find.text('Send to HR'), findsOneWidget, reason: 'the photo is kept so it can be sent later');
  });
}
