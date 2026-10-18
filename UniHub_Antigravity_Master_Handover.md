# UniHub --- Master Project Handover for Antigravity

**Document date:** 18 October 2026\
**Project:** UniHub --- multi-university student companion app\
**Current development environment:** GitHub Codespaces\
**Primary target:** Android app / APK\
**Highest-priority feature:** Push notifications

> Use this document as project context, not as proof that every feature
> is complete. Inspect the repository and Supabase configuration before
> changing code. Keep existing work unless a change is necessary and
> explain why.

------------------------------------------------------------------------

## 1. Project vision

UniHub is intended to be one app for students across multiple
universities. It should support university-specific and
department-specific information while allowing the platform to grow into
a multi-university system.

Planned modules include:

-   Authentication and user profile
-   Push notifications and in-app notification centre
-   Notices
-   Class routines and routine-change alerts
-   Library files/resources
-   Student profile and settings
-   CR (class representative) tools
-   Admin and super-admin panels
-   Later possibilities: attendance, results, assignments, events,
    discussion, and other student services

### Product principle

**Push notification is Priority #1.** Build the architecture so future
features (notice publishing, routine changes, results, emergency
announcements, etc.) can create targeted notifications without needing a
separate notification system each time.

## 2. Technology stack and development setup

Known stack:

-   Flutter / Dart
-   Supabase Auth, PostgreSQL database, and Row Level Security (RLS)
-   `supabase_flutter: ^2.16.0`
-   `flutter_dotenv: ^6.0.1`
-   `flutter_riverpod`
-   `go_router`
-   GitHub repository and GitHub Codespaces
-   Firebase Cloud Messaging (FCM) is planned; integration is **not
    confirmed complete**
-   Supabase Edge Functions are the proposed secure server-side sender
    for FCM

The developer is building in Codespaces. `flutter run` attempted to run
the **Linux desktop** target and failed because the environment lacked
Ninja/CMake build tooling. This does not by itself indicate a Flutter
source-code problem. Prefer checking `flutter devices`, configuring an
Android emulator/device where available, or building an Android APK once
the Android toolchain is configured. Do not assume an Android emulator
exists inside the current Codespace.

## 3. Supabase project

-   Project URL: `https://mnxltkkbfzdspelkrjai.supabase.co`
-   Project ref: `mnxltkkbfzdspelkrjai`
-   Region: Singapore
-   `.env` contains:
    -   `SUPABASE_URL`
    -   `SUPABASE_ANON_KEY` (the project publishable/anon client key)

**Security:** Never ask the developer to paste `.env`, access tokens,
service-role keys, FCM server credentials, or other secrets into chat or
commit them to Git. Keep service-role credentials only in secure
server-side Supabase secrets. Confirm `.env` is ignored by Git and never
expose private keys in Flutter code.

### Known database setup

A PostgreSQL enum was created:

`public.user_role` - `student` - `cr` - `admin` - `super_admin`

Tables created in Supabase: - `universities` - `departments` - `users` -
`notices` - `routines` - `library_files`

RLS was enabled during setup. **Do not assume the required policies,
foreign keys, or columns are correct yet.** Inspect the actual schema
and policies before implementing database writes. The exact schema for
these tables has not been fully documented in the handover context.

## 4. Current Flutter structure

The project structure recorded so far:

``` text
lib/
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme.dart
├── core/
│   ├── config/
│   ├── constants/
│   ├── services/
│   │   └── supabase_service.dart
│   └── utils/
├── features/
│   ├── auth/
│   │   ├── auth_service.dart
│   │   ├── login_screen.dart
│   │   └── verify_otp_screen.dart
│   ├── home/
│   │   └── home_screen.dart
│   ├── library/
│   ├── notice/
│   ├── profile/
│   ├── routine/
│   ├── settings/
│   └── splash/
│       └── splash_screen.dart
├── shared/
│   ├── providers/
│   │   └── auth_provider.dart
│   └── widgets/
└── main.dart
```

There was previously an accidental duplicate at
`lib/services/supabase_service.dart`. It was removed. The intended
service is:

`lib/core/services/supabase_service.dart`

``` dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final client = Supabase.instance.client;
}
```

Inspect the live repository because the tree may have changed since this
snapshot.

## 5. Current known code and status

### `main.dart`

Supabase is initialized using `flutter_dotenv` and the current
`supabase_flutter` API:

``` dart
await dotenv.load(fileName: ".env");

await Supabase.initialize(
  url: dotenv.env['SUPABASE_URL']!,
  publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
);
```

Inspect the actual file and ensure initialization errors are handled
appropriately without exposing secrets.

### `lib/features/auth/auth_service.dart`

The last recorded version:

``` dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/supabase_service.dart';

class AuthService {
  final SupabaseClient _client = SupabaseService.client;

  User? get currentUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  Future<void> signInWithEmailOtp(String email) async {
    await _client.auth.signInWithOtp(
      email: email,
      shouldCreateUser: true,
    );
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.email,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  bool get isLoggedIn => currentUser != null;
}
```

This code was written, but real email delivery and OTP verification have
**not been confirmed by an end-to-end test**. Verify the Supabase email
template and whether the configured email flow sends a numeric OTP or a
magic link. Align the UI and `verifyOTP` type with the actual
configuration.

### `lib/features/auth/login_screen.dart`

The last recorded UI has: - UniHub welcome screen - University email
input - Continue button - Loading state - Calls
`signInWithEmailOtp(email)` - On success navigates to `/verify` and
passes the email as `extra` - Shows a SnackBar on errors

Basic empty-email validation exists. More robust email validation and
accessibility can be added later.

### `lib/features/auth/verify_otp_screen.dart`

The last recorded screen: - Accepts an `email` argument - Six-character
OTP text field - Calls
`authService.verifyOtp(email: widget.email, token: ...)` - Navigates to
`/home` on success - Shows errors via SnackBar

OTP screen navigation and verification are implemented in code, but not
confirmed against a real email.

### `lib/app/router.dart`

The last recorded router includes: - Initial location `/splash` -
`/splash`, `/`, `/verify`, `/home` - Redirect reads
`Supabase.instance.client.auth.currentUser` - Logged-out users are
allowed at `/`, `/verify`, and `/splash` - Logged-in users at `/` or
`/splash` are redirected to `/home` - `/home` is otherwise protected by
redirect

A Dart lint warning was fixed by replacing unused `(_, __)` builder
arguments with `(context, state)` for routes where both arguments are
unused. After that, `flutter analyze` reported **No issues found!**

**Important architectural caveat:** this router reads the current user
during redirect but is not yet wired to refresh automatically on
Supabase auth-state changes. Login/logout redirects may therefore be
stale in some navigation paths. The current `/verify` route also casts
`state.extra as String`; opening that route without an email could
throw. Improve these safely after inspecting all current files,
preferably by wiring GoRouter refresh to `onAuthStateChange` and
validating route arguments.

### `lib/app/app.dart`

Last recorded code:

``` dart
import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class UniHubApp extends StatelessWidget {
  const UniHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'UniHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: AppRouter.router,
    );
  }
}
```

### `lib/features/splash/splash_screen.dart`

The last recorded version waits two seconds, then checks
`Supabase.instance.client.auth.currentUser` and navigates to `/home` or
`/`. It shows a centered `CircularProgressIndicator`. Review whether the
delay and duplicate redirect logic are needed once router auth refresh
is implemented.

### `lib/features/home/home_screen.dart`

Last recorded screen is a placeholder with an AppBar titled `UniHub` and
a welcome message. This is not the final dashboard.

### Riverpod auth providers

Last recorded `lib/shared/providers/auth_provider.dart`:

``` dart
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.currentUser;
});
```

Inspect the actual imports and usage before changing it.

## 6. Git / current checkpoint

-   Git branch: `main`
-   Repository was previously reported as `sanaullahbd501/unihub` in
    `/workspaces/unihub`, but verify the current Git remote before
    relying on it.
-   The last `git status` showed only `lib/app/router.dart` modified,
    due to the lint fix.
-   The next intended commands were:

``` bash
git add lib/app/router.dart
git commit -m "style(router): fix GoRouter builder lint warnings"
git push origin main
git status
```

**Do not assume these commands have already been run.** First inspect
`git status`, the latest commit, and remote status. Do not overwrite or
discard uncommitted work.

A prior `flutter analyze` run after the lint fix showed
`No issues found!`. A subsequent `flutter run` tried the Linux desktop
target and failed because Ninja/CMake tooling was missing. No Android
runtime test has been confirmed.

## 7. Push notifications --- highest priority

This is the most important product requirement. Implement the design
with security and targeting from the beginning.

### Desired user-side features

-   Register FCM token(s) for each device
-   Foreground notifications
-   Background notifications
-   Handle app launch when a notification is tapped
-   In-app notification centre
-   Read/unread status
-   Deep link to the relevant notice, routine, result, or other content
-   Handle token refresh and token deactivation on logout where
    appropriate

### Desired targeting

-   Everyone / emergency broadcast
-   University
-   Department
-   Batch / semester (when schema supports it)
-   CR-only
-   Individual user
-   Potentially scheduled notifications

### Notification categories

-   `NOTICE`
-   `ROUTINE`
-   `RESULT`
-   `ASSIGNMENT`
-   `EXAM`
-   `EVENT`
-   `PAYMENT`
-   `LIBRARY`
-   `GENERAL`
-   `EMERGENCY`

### Proposed architecture

``` text
Flutter app
  └── obtains FCM registration token
        └── saves token securely in Supabase under authenticated user

Admin / CR action (authorized server-side)
  └── creates notification record / audience
        └── Supabase Edge Function
              └── validates caller permissions and target scope
                    └── sends via Firebase Cloud Messaging
                          └── user device receives push
                                └── tap opens correct in-app destination
```

Potential tables to design after inspecting the existing schema: -
`notification_tokens` - `notifications` - `notification_receivers` (or a
scalable equivalent) - `notification_logs` (optional operational audit)

Do not blindly create these tables without checking current database
migrations and naming conventions.

### Critical security rules

-   Never put Firebase service-account credentials or FCM server secrets
    in Flutter/client code.
-   Store server credentials in Supabase Edge Function secrets.
-   Only trusted server-side code can send messages.
-   Enforce authorization on the server: a student must not be able to
    send a broadcast or target another department.
-   Validate university, department, batch, CR/admin role, and recipient
    audience server-side.
-   RLS must restrict access to device tokens, notification records, and
    recipient status.
-   Avoid leaking recipient lists or tokens to ordinary users.
-   Design duplicate-token handling, token refresh, invalid-token
    cleanup, retry/error logging, and safe failure handling.
-   Decide whether to store one token per device and support multiple
    devices per account.
-   For emergency notifications, use explicit authorization and audit
    logs.

### Recommended implementation order for FCM

1.  Inspect Flutter Android project (`android/`), Gradle config,
    package/application ID, and toolchain.
2.  Confirm/create Firebase project and register the Android app using
    the correct application ID.
3.  Add Firebase configuration without committing private credentials.
    Follow current FlutterFire setup for the environment.
4.  Add `firebase_core` and `firebase_messaging`, configure Android
    notification channel/permissions and app lifecycle handling.
5.  Get the FCM token on a physical Android device and handle refresh.
6.  Create/confirm secure Supabase table and RLS policies for device
    tokens.
7.  Save the token for the signed-in user.
8.  Implement a server-side Supabase Edge Function that sends a test
    push using secure Firebase credentials.
9.  Test foreground, background, terminated-app tap, and invalid-token
    behavior.
10. Build the in-app notification centre and targeting.
11. Integrate notice/routine publishing with the same notification
    engine.

Push notifications are **planned, not implemented yet** in the recorded
project state.

## 8. User profile and role system

The database has a `public.users` table and the `public.user_role` enum.
Desired first-login behavior: - Link profile to Supabase Auth user ID
(`auth.users.id`) - Email - Full name (can be filled later) -
University - Department - Role defaults to `student` - Created/updated
timestamps

Potential later profile attributes include batch/semester, but confirm
schema and product decisions before adding fields.

Important: - Do not assume `public.users` columns or constraints;
inspect them. - Use an idempotent upsert/create strategy so repeat login
does not create duplicate profiles. - Ensure RLS allows a user to
create/update only their own allowed profile fields. - Do not let a
client choose or elevate its own role to `cr`, `admin`, or
`super_admin`. - Privileged role changes must be performed by trusted
administrative code. - Plan an appropriate foreign-key relationship
between profile and `auth.users`. - Handle existing auth users whose
profile is missing.

## 9. Suggested development roadmap

### Phase A --- stabilize and verify current authentication

-   Inspect repository, `.env` handling, `pubspec.yaml`, current router,
    and auth files.
-   Confirm `flutter analyze`.
-   Fix router refresh/session restore and route argument safety.
-   Test actual OTP email flow with Supabase configuration.
-   Test app restart/session restoration on Android.
-   Implement logout and confirm redirects.
-   Create user profile safely in `public.users`.
-   Verify RLS and role protections.

### Phase B --- FCM foundation (first major feature)

-   Firebase project and Android setup
-   FCM permissions/token retrieval
-   Secure token registration in Supabase
-   Edge Function to send a test notification
-   Foreground/background/tap handling
-   Test on a real Android device
-   Notification persistence and in-app history

### Phase C --- Smart notification engine

-   Audience targeting
-   Notification receiver/read status
-   Deep links
-   Audit logs and retry handling
-   Admin/CR authorization
-   Emergency broadcast
-   Scheduled notifications if needed

### Phase D --- Feature modules

-   Notices with push integration
-   Routines with change alerts
-   Library resources with update alerts
-   Profile and settings
-   CR tools
-   Admin/super-admin dashboard
-   Later attendance/results/assignments and other features

## 10. Working style and implementation rules

The developer prefers: - Bengali communication for explanations, with
common technical terms in English. - Clear, practical, step-by-step
instructions. - Complete files to replace when a change spans a file,
rather than many scattered snippets. - One manageable milestone at a
time. - Explicit commands to run and what output to share. - Commit/push
checkpoints at stable milestones. - Avoid wasting paid/free AI usage
with unnecessarily long, speculative work.

When working in Antigravity: 1. Inspect the actual repository before
editing. 2. Start with a concise plan and identify files to change. 3.
Do not rewrite unrelated code or start from scratch. 4. Keep changes
small enough to review but deliver complete coherent features. 5. Run
`flutter analyze` after edits. 6. Run tests/builds only when the
required SDK/device/tooling exists; clearly state what was and was not
tested. 7. Never claim a feature works until it has been tested. 8. Show
a concise summary of changed files, commands, results, and any remaining
manual setup. 9. Avoid changing Supabase schema without showing the
SQL/migration and explaining RLS implications. 10. Keep credentials out
of source control and logs.

## 11. First task for Antigravity

Begin with **read-only inspection** of the existing project. Do not make
code changes yet.

Inspect: - `git status`, latest commit, and remote - `pubspec.yaml` -
`lib/main.dart` - `lib/app/router.dart` - `lib/app/app.dart` -
`lib/features/auth/auth_service.dart` -
`lib/features/auth/login_screen.dart` -
`lib/features/auth/verify_otp_screen.dart` -
`lib/features/splash/splash_screen.dart` - Android app ID / Gradle
files - `.gitignore` and whether `.env` is excluded - Existing Supabase
migrations/schema files - Whether Firebase/FCM dependencies or
configuration already exist

Then report: 1. What is truly implemented versus only planned. 2. Any
immediate security or correctness risks. 3. Whether the current working
tree has uncommitted changes. 4. The smallest safe next step, keeping
**push notification as the top product priority**.

Do not ask the developer to paste secrets. Do not add Firebase or create
database tables before this inspection and plan are complete.

------------------------------------------------------------------------

## 12. Quick project status snapshot

  -----------------------------------------------------------------------
  Area                                Current known status
  ----------------------------------- -----------------------------------
  Flutter project                     Initialized

  Supabase initialization             Code exists; inspect current repo

  Email OTP login UI                  Code exists; real flow unverified

  OTP verification screen             Code exists; real flow unverified

  GoRouter                            Basic routes exist; auth refresh
                                      needs improvement

  Splash screen                       Basic screen and session check
                                      exist

  Session restore                     Not verified end-to-end

  Logout                              Auth service method exists;
                                      UI/redirect not verified

  `public.users` profile auto-create  Pending

  Role-based routing/access           Pending

  Supabase tables                     Created; actual schema/RLS policies
                                      need inspection

  FCM                                 Not yet confirmed integrated

  Push notification engine            Pending; top priority

  Notice/routine/library modules      Structure exists; features pending

  `flutter analyze`                   Last reported clean after router
                                      lint fix

  Android runtime/APK test            Not yet confirmed

  Linux `flutter run`                 Failed because Ninja/CMake tooling
                                      was missing for Linux desktop
  -----------------------------------------------------------------------

**End of handover.**
