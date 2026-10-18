# UniHub --- Full Detailed Product & Technical Plan

**Version:** 1.0\
**Prepared:** 18 October 2026\
**Product:** UniHub --- a multi-university student companion app\
**Primary launch target:** Android\
**Primary technical stack:** Flutter + Supabase + Firebase Cloud
Messaging\
**Top priority:** Push notification system

------------------------------------------------------------------------

# 1. Executive Summary

UniHub is a multi-university platform that helps students access
university-specific academic information from one mobile app. It
combines timely notifications, notices, class routines, learning
resources, student profiles, and role-based tools for Class
Representatives (CRs) and administrators.

The product must be designed as a scalable multi-tenant application:
every record belongs to a university and, where relevant, a department,
batch, semester, or specific user. A user should only see information
they are authorized to access.

The most important product differentiator is a reliable **push
notification system**. It should support general broadcasts,
university/department targeting, routine changes, new notices, emergency
alerts, and future features such as results and assignments. Other
modules should publish events into one shared notification engine.

This is a plan, not a statement that all features are already
implemented. The current repository, Supabase schema, Firebase setup,
and runtime behavior must be audited before implementation.

## Product goals

1.  Deliver relevant university information quickly.
2.  Avoid missing urgent announcements through dependable push
    notifications.
3.  Keep notices, routines, and learning resources organized by
    university and department.
4.  Provide controlled workflows for students, CRs, admins, and
    super-admins.
5.  Support additional universities without forking the app.
6.  Keep operating costs low at the start while preserving a path to
    scale.
7.  Protect student data, notification tokens, and privileged
    operations.

## Initial non-goals

Avoid building everything at once. The first release does not need: - A
full learning management system - Live chat or social networking -
Payment processing - A complete attendance management system - An
exam/result management system unless a concrete data source and
permission model are agreed - An elaborate analytics suite - A web admin
portal before core mobile workflows work

These can be added after the notification, notice, routine, and profile
foundations are stable.

------------------------------------------------------------------------

# 2. Users, Roles, and Permissions

Use the existing role enum as the starting point:

-   `student`
-   `cr`
-   `admin`
-   `super_admin`

Do not allow users to assign themselves elevated roles from the client.

## 2.1 Student

Can: - Sign in using the configured email OTP flow - Maintain permitted
profile fields - Select/view their university, department, batch and
semester where applicable - Receive targeted notifications - View
notification history and read/unread state - View notices, routines, and
permitted library resources - Open the relevant item from a
notification - Manage notification preferences within policy - Sign out
and manage their registered devices

Cannot: - Send broadcast notifications - Change their own role - Read
other students' private profiles or device tokens - Modify official
notices/routines unless separately authorized

## 2.2 Class Representative (CR)

Can, depending on explicit university policy: - Submit a draft notice or
routine correction for approval - Send an announcement only to the
permitted class/department audience if CR notification sending is
enabled - See delivery/error status for their own authorized sends, not
private tokens - Help maintain class information

Should not automatically receive broad admin privileges. CR capabilities
should be represented by server-validated permissions, not just hidden
UI buttons.

## 2.3 University Admin

Can: - Manage the assigned university's departments and academic
information - Create, edit, publish, archive notices - Create and
publish routines or routine-change alerts - Send notifications to
authorized audiences within that university - View operational delivery
summaries and audit history - Manage permitted user/profile metadata

Cannot manage other universities unless explicitly granted cross-tenant
access.

## 2.4 Super Admin

Can: - Manage the platform and onboard universities - Assign university
admins - Manage global categories and platform configuration - Send
global emergency alerts under explicit policy - Review system health and
audit logs

Super-admin actions must be auditable and protected with stronger
controls.

------------------------------------------------------------------------

# 3. Product Scope and Priorities

## Priority 0 --- Foundations

-   Repository and configuration audit
-   Environment/secrets hygiene
-   Stable navigation and authentication
-   Database schema and RLS review
-   Android build pipeline

## Priority 1 --- Push Notifications (highest feature priority)

-   Firebase setup
-   Device token registration and refresh
-   Foreground/background notification handling
-   Notification tap/deep-link handling
-   Secure server-side sending
-   In-app notification history
-   Audience targeting
-   Delivery logging and invalid-token cleanup

## Priority 2 --- Notices

-   Notice list and detail
-   Search/filter by category and date
-   University/department/batch visibility
-   Draft/publish/archive workflow
-   Push notification triggered on publish

## Priority 3 --- Routine

-   Routine by department/batch/semester
-   Routine detail and relevant file/link
-   Routine update/change history
-   Push notification for changes to affected students

## Priority 4 --- Library

-   Searchable resources and categories
-   Supabase Storage or approved external links
-   Permission-aware file access
-   New-resource notification where useful

## Priority 5 --- Profile and Settings

-   Profile completion
-   University/department/batch/semester assignment
-   Device management
-   Notification preferences
-   Logout

## Priority 6 --- CR Tools

-   Draft announcements
-   Routine correction requests
-   Class-specific communication under policy
-   Limited audience selection
-   Approval workflow

## Priority 7 --- Admin Panel

-   Manage notices/routines/library
-   Publish notifications
-   Manage audiences within authority
-   Review audit and delivery summaries

## Priority 8 --- Super Admin and Platform Operations

-   University onboarding
-   Admin assignment
-   Global emergency announcements
-   Operational monitoring and abuse prevention

## Later possibilities

-   Attendance
-   Results
-   Assignments
-   Events
-   Discussion/community
-   Calendar integration
-   Analytics
-   Web admin dashboard
-   iOS support

------------------------------------------------------------------------

# 4. Core User Journeys

## 4.1 First launch and login

1.  User opens the app.
2.  Splash/auth-state resolution runs.
3.  If no session exists, show login.
4.  User enters email and requests OTP.
5.  Supabase sends the configured OTP/magic-link flow.
6.  User verifies the OTP.
7.  App retrieves authenticated user identity.
8.  App creates or retrieves the associated `public.users` profile using
    an idempotent server/database-safe approach.
9.  If profile details are incomplete, prompt the user to complete them.
10. Once authorized, register the device for FCM and save the token.
11. Navigate to the Home dashboard.

## 4.2 Returning user

1.  Supabase restores a valid session.
2.  Router listens to auth-state changes and resolves the destination.
3.  User goes to Home without signing in again.
4.  FCM token is refreshed/reconciled when needed.

## 4.3 Receive and open notification

1.  Server creates a notification record and determines eligible
    recipients.
2.  Server sends FCM messages to the recipients' active device tokens.
3.  App receives notification in foreground/background according to
    platform behavior.
4.  The notification appears in the OS notification shade where
    applicable.
5.  User taps it.
6.  App validates the destination and opens the correct
    notice/routine/detail screen.
7.  Notification is marked read for that user.
8.  The in-app notification centre reflects the state.

## 4.4 Publish a notice

1.  Authorized admin creates a draft notice.
2.  Required fields and audience are validated.
3.  Admin publishes.
4.  Database stores the published notice and audit information.
5.  A secure server-side process creates a notification event.
6.  Targeting rules determine eligible users.
7.  FCM sends the push.
8.  Notification history links to the notice.

## 4.5 Change a routine

1.  Authorized person updates the routine.
2.  The system records what changed and who changed it.
3.  The affected audience is resolved.
4.  A notification states the useful change, not just "routine updated."
5.  Tapping opens the relevant routine and, if possible, highlights the
    changed day/class.

------------------------------------------------------------------------

# 5. Technical Architecture

## 5.1 Client

Flutter app responsibilities: - UI and navigation - Auth session
display - Read authorized data from Supabase - Request/maintain FCM
permission and token - Display notifications and notification history -
Send authorized user actions - Never hold server service-role or
Firebase server credentials

Suggested feature-first structure:

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
│   └── utils/
├── features/
│   ├── auth/
│   ├── notifications/
│   ├── home/
│   ├── notice/
│   ├── routine/
│   ├── library/
│   ├── profile/
│   ├── cr/
│   ├── admin/
│   └── settings/
├── shared/
│   ├── providers/
│   └── widgets/
└── main.dart
```

Add folders as the corresponding feature begins; do not create empty
scaffolding for every future feature prematurely.

## 5.2 Supabase

Use for: - Authentication - PostgreSQL database - Row Level Security -
Optional Storage for library files - Edge Functions for trusted
server-side actions - Operational event records

## 5.3 Firebase

Use Firebase Cloud Messaging for device delivery. Firebase credentials
needed to send messages must remain server-side. Follow the current
Firebase/FlutterFire setup instructions and Android requirements at
implementation time.

## 5.4 Event-driven notification engine

Feature actions should create domain events, such as: -
`notice.published` - `routine.changed` - `library.resource_published` -
`result.published` (future) - `emergency.broadcast`

The notification engine maps each event to: - Title/body -
Category/type - Target audience - Destination/deep link - Priority -
Audit metadata

A database transaction should persist the domain change and event/outbox
record where feasible. A worker/Edge Function processes pending events.
Use retries and idempotency to avoid duplicate pushes. Do not rely only
on client-side code to trigger official notifications.

------------------------------------------------------------------------

# 6. Database Design Proposal

**Important:** These are proposed concepts. Inspect existing tables,
columns, constraints, indexes, and RLS policies before writing
migrations. Reuse or adapt existing schema where appropriate.

## 6.1 Existing known tables

-   `universities`
-   `departments`
-   `users`
-   `notices`
-   `routines`
-   `library_files`

Existing enum: - `public.user_role`: `student`, `cr`, `admin`,
`super_admin`

The current actual schema is not fully documented. Confirm it from
migrations or Supabase before coding.

## 6.2 User profile

Conceptual fields: - `id`: profile primary key - `auth_user_id`: foreign
key to `auth.users.id`, unique - `email` - `full_name` -
`university_id` - `department_id` - `batch` or `batch_id` if the product
uses batch targeting - `semester` or `semester_id` if needed - `role` -
`created_at` - `updated_at`

Role defaults to `student`. Never trust client-provided role updates.

## 6.3 Device tokens

Proposed `notification_tokens`: - `id` - `user_id` - `fcm_token` (unique
or uniquely scoped according to design) - `platform` - `device_label`
(optional, avoid unnecessary fingerprinting) - `is_active` -
`last_seen_at` - `created_at` - `updated_at`

Allow multiple devices per account. Handle token refresh, duplicate
registration, logout policy, and invalid-token cleanup.

## 6.4 Notification record

Proposed `notifications`: - `id` - `title` - `body` - `type` -
`target_type` - `target_id` or structured audience fields -
`deep_link` - `created_by` - `created_at` - `scheduled_at` (optional) -
`sent_at` - `status` - `priority` - `data` (limited structured payload)

Keep the content shown in-app even if push delivery fails.

## 6.5 Recipient/read state

Possible `notification_receivers`: - `id` - `notification_id` -
`user_id` - `delivery_status` if tracked per recipient - `delivered_at`
where delivery evidence is available - `read_at` - `created_at`

For large broadcasts, avoid creating excessive rows unless per-user
history/read state requires it. Consider audience membership snapshots
or another scalable model. FCM acceptance is not proof that a device
displayed the notification; distinguish "accepted by FCM," "device
received" where measurable, and "read in app."

## 6.6 Audit and event processing

Potential `notification_logs` / `notification_outbox`: - Event ID -
Notification ID - Target summary - Attempt count - Status - Error
code/message with secrets and personal data removed -
Created/updated/processed timestamps

Use idempotency keys and bounded retries.

------------------------------------------------------------------------

# 7. Security and RLS

Security is part of the feature, not a later task.

-   Enable and verify RLS for all tables containing user, device-token,
    notification, and academic data.
-   Students can read only their own private profile fields and
    notifications plus public/authorized university content.
-   A user can never elevate their own role.
-   CR permissions must be scoped to the approved
    university/department/batch.
-   University admins must be scoped to their own university.
-   Only trusted server-side code can send FCM.
-   Service-role keys and Firebase service-account credentials stay in
    server-side secrets.
-   Validate all audience selectors on the server; do not trust client
    filters.
-   Do not expose FCM tokens to other users.
-   Avoid logging raw tokens, OTPs, service credentials, or private
    student information.
-   Rate-limit notification sends and prevent repeated accidental
    broadcasts.
-   Require confirmation for emergency/global sends and write an audit
    record.
-   Use minimum necessary data in push payloads; avoid sensitive details
    that appear on a locked screen.
-   Validate deep-link IDs and permissions after opening a notification.
-   Establish retention/deletion rules for logs and inactive tokens.

------------------------------------------------------------------------

# 8. Push Notification Detailed Plan

## Milestone 1 --- Firebase/Android readiness

-   Inspect Android package/application ID.
-   Check Gradle and Android SDK configuration.
-   Confirm Firebase project access and register the matching Android
    app.
-   Configure Firebase for Flutter using the current supported setup.
-   Verify configuration files are not secrets and are placed correctly.
-   Add required dependencies and initialize Firebase.
-   Build and run on a real Android device when possible.

**Exit criteria:** app starts on Android with Firebase initialized; no
private sending credential is embedded in the app.

## Milestone 2 --- Permission and token

-   Request notification permission at a sensible time.
-   Obtain the FCM registration token.
-   Handle token refresh.
-   Handle permission denied and token unavailable states gracefully.
-   Register token for the authenticated user through an RLS-safe
    approach.
-   Reconcile tokens after login and on app start as appropriate.
-   Decide and implement logout behavior for device registration.

**Exit criteria:** test device token is stored against the correct user;
no other user can read or modify it.

## Milestone 3 --- Secure test sender

-   Store Firebase server credentials in Supabase Edge Function secrets.
-   Implement an Edge Function that authenticates the caller or accepts
    only an authorized trusted trigger.
-   Verify the caller's role and audience permission server-side.
-   Send a test notification to a specific authorized test device.
-   Persist send attempt and error status without logging secrets.

**Exit criteria:** authorized test push arrives; unauthorized caller
cannot send.

## Milestone 4 --- App lifecycle handling

Test: - Foreground - Background - App terminated, then notification
tapped - Notification permission denied - Token refresh -
Invalid/unregistered token - Network unavailable - User signed out -
User signed into another account on the same device

Use Android notification channels and proper priority/category
configuration. Test on a physical device because simulator behavior may
differ.

**Exit criteria:** app behaves predictably in each supported state.

## Milestone 5 --- In-app notification centre

-   List notifications the current user is authorized to see.
-   Mark individual notification read.
-   Mark all read if desired.
-   Show unread count.
-   Filter by type and date.
-   Open the linked content.
-   Keep the record available even if OS push was missed.
-   Provide empty/loading/error states.

**Exit criteria:** read state persists across app restarts and cannot be
modified for another user.

## Milestone 6 --- Targeting

Implement in a safe order: 1. Individual test user 2. All users within
one university 3. Department 4. Batch/semester if data model supports it
5. CR-only audience 6. Platform-wide emergency broadcast

For every audience, resolve recipients on the server and check the
sender's authority. Show a recipient estimate and require confirmation
for broad sends.

**Exit criteria:** tests prove users outside the audience do not receive
the notification.

## Milestone 7 --- Connect notices and routines

-   Publishing a notice creates a notification event.
-   Changing a routine creates a change event.
-   Event processing is idempotent.
-   Failed push attempts can retry.
-   Notification tap opens the correct detail page.
-   Admin sees delivery summary and relevant errors.

**Exit criteria:** one publish/change action results in one persisted
notification and no unintended duplicate push.

------------------------------------------------------------------------

# 9. UI/UX Plan

Use a clear, student-friendly interface with consistent navigation and
accessible text sizes. Do not spend excessive time polishing the Home
dashboard before notification flows work.

## Initial navigation

Suggested bottom navigation after core modules exist: - Home - Notices -
Routine - Library - Profile

Notifications should be readily accessible from the app bar and may have
an unread badge. Keep admin/CR navigation role-aware.

## Home dashboard

Potential cards: - Latest notices - Today's routine - Upcoming
exams/events (only when data exists) - Unread notification count - Quick
access to Library - Emergency banner when an active emergency notice
exists

Use skeleton/loading states, empty states, retry actions, and meaningful
error messages.

## Notification list item

Display: - Type icon/label - Title - Short body - Time - Read/unread
styling - Tap action

Do not rely on color alone to indicate unread state.

------------------------------------------------------------------------

# 10. Testing and Quality Plan

## Code quality

-   Run `flutter analyze` after each coherent change.
-   Format Dart files.
-   Add unit tests for audience selection, routing, and event mapping
    where feasible.
-   Add integration tests for authentication and notification routing
    where feasible.
-   Review dependencies and Android build configuration.
-   Keep a clean Git checkpoint after stable milestones.

## Security tests

-   Student cannot read another user's token or private notification.
-   Student cannot send broadcasts.
-   CR cannot target unauthorized classes/departments.
-   Admin cannot manage another university.
-   Client cannot change role to admin/super-admin.
-   Invalid deep links do not reveal unauthorized content.
-   No service credential exists in the Flutter bundle or Git history.

## Release checks

-   Real Android device login
-   OTP/email behavior confirmed
-   Session survives app restart
-   Logout works and routing refreshes
-   FCM token saved and refreshed
-   Push tested in foreground/background/terminated states
-   Tap opens the intended screen
-   Notification history/read state works
-   Database RLS verified
-   Android APK builds successfully
-   Git status and secrets checked before release

------------------------------------------------------------------------

# 11. Build, Git, and Development Workflow

## At the start of a session

1.  Check `git status`.
2.  Check latest commit and current branch.
3.  Read current implementation before changing it.
4.  Check Flutter version and available devices.
5.  Read relevant schema/migrations before database changes.
6.  Write a small plan for the next milestone.

## After each milestone

1.  Implement a coherent change.
2.  Run formatter and `flutter analyze`.
3.  Run tests/build only where the environment supports them.
4.  Review the diff.
5.  Check that secrets and local config are not staged.
6.  Commit with a clear message.
7.  Push to the intended remote if appropriate.
8.  Record what remains untested.

Suggested commit style: -
`fix(auth): refresh router on auth state changes` -
`feat(profile): create profile after first login` -
`feat(notifications): register FCM device token` -
`feat(notifications): send secure test push` -
`feat(notifications): add in-app notification centre` -
`feat(notice): notify audience when notice is published`

Do not commit if analysis fails or the change is known to be incomplete
unless the commit is explicitly a work-in-progress checkpoint.

## Codespaces caveat

A `flutter run` attempt previously selected Linux desktop and failed
because Ninja/CMake build tools were unavailable. That is not proof of
Android build failure. Check `flutter devices`, Android SDK/Gradle
setup, and use a physical device or supported Android build pipeline. Do
not waste time installing Linux desktop dependencies if Android is the
target.

------------------------------------------------------------------------

# 12. Current Known Status (Must Be Re-Verified)

  -----------------------------------------------------------------------
  Component                           Known status
  ----------------------------------- -----------------------------------
  Flutter project                     Initialized

  Supabase client setup               Code exists

  Supabase auth                       OTP methods exist in code; real
                                      email flow unverified

  Login screen                        Code exists

  OTP verification screen             Code exists; end-to-end test
                                      unverified

  GoRouter                            Basic routes exist; auth-state
                                      refresh needs review

  Splash                              Basic session check exists

  Session restoration                 Not confirmed by test

  Logout                              Service method exists; UI/redirect
                                      unverified

  `public.users` profile sync         Pending

  Role-aware authorization            Pending

  Existing database tables            Created; schema/RLS must be
                                      inspected

  Firebase project/configuration      Not confirmed

  FCM token registration              Pending

  Secure push sender                  Pending

  Notification history                Pending

  Targeted notifications              Pending

  Notice module                       Structure exists; functionality
                                      needs verification

  Routine module                      Structure exists; functionality
                                      needs verification

  Library module                      Structure exists; functionality
                                      needs verification

  Android APK/device test             Not confirmed

  `flutter analyze`                   Last reported clean after router
                                      lint fix

  Git checkpoint                      Verify current status before
                                      committing
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# 13. Suggested Release Plan

## Internal Prototype

-   Authentication works on Android
-   Profile row is created safely
-   One test device can register FCM
-   Secure test push works
-   Notification tap opens app

## MVP

-   Notification centre and read/unread
-   Notices with university/department targeting
-   Routine view and routine-change notifications
-   Library list/resources
-   Admin publishing flow with audit records
-   RLS and authorization tests

## Wider Pilot

-   Multiple universities
-   University-specific admins
-   CR approval workflows
-   Batch/semester targeting
-   Delivery health monitoring and retry handling
-   User feedback and usability fixes

## Public Release

-   Stable Android builds
-   Tested onboarding and recovery paths
-   Privacy policy and terms
-   Support/reporting path
-   Backup/restore and operational procedures
-   Performance/security review
-   Defined retention and incident-response processes

Release criteria should be based on verified behavior, not on the number
of screens or files created.

------------------------------------------------------------------------

# 14. First Instructions for Antigravity

Use this plan alongside the existing Master Handover document.

1.  Start with read-only repository audit.
2.  Confirm actual Git status, remote, latest commit, and all
    uncommitted work.
3.  Inspect auth code, `pubspec.yaml`, `.gitignore`, Android app
    ID/Gradle, and Supabase migrations.
4.  Verify whether Firebase is already configured.
5.  Report implemented vs planned vs tested.
6.  Identify security issues and blockers.
7.  Recommend the smallest safe next step.
8.  Keep push notifications as the highest feature priority.
9.  Do not create schema or credentials before confirming the design and
    existing setup.
10. After approval, implement one milestone at a time, analyze/test,
    summarize changed files, and provide exact next steps.

**Core rule:** Build UniHub as a secure multi-university student app
with a reusable, server-authorized notification engine at its center.
Verify each milestone before moving to the next.
