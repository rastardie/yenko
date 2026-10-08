import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yenko_app/core/data/admin_api_client.dart';
import 'package:yenko_app/core/data/local_auth_client.dart';
import 'package:yenko_app/core/data/trip_repository.dart';
import 'package:yenko_app/features/admin/admin_screen.dart';
import 'package:yenko_app/features/admin/admin_reports_screen.dart';
import 'package:yenko_app/features/navigation/yenko_root_screen.dart';
import 'package:yenko_app/shared/widgets/sign_out.dart';

/// Minimal admin API double that records requests and serves canned JSON.
class _FakeAdminServer {
  _FakeAdminServer._(this._server);

  static Future<_FakeAdminServer> start() async {
    final fake = _FakeAdminServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fake._server.listen(fake._handle);
    return fake;
  }

  final HttpServer _server;
  final requests = <String>[];
  final authorization = <String?>[];
  final actionHeaders = <String?>[];
  int forbiddenStatus = 0;
  int rejectActionTokens = 0;
  int tokenCounter = 0;
  bool twoUsers = false;

  String get baseUrl =>
      'http://${InternetAddress.loopbackIPv4.address}:${_server.port}';

  Future<void> close() => _server.close(force: true);

  static const _user = {
    'id': 'user-1',
    'displayName': 'Kofi Mensah',
    'username': 'kofi',
    'status': 'active',
    'createdAt': '2026-10-01T10:00:00.000Z',
    'groups': [
      {'id': 'g-riders', 'name': 'Riders', 'role': 'passenger'},
    ],
    'roles': ['passenger'],
  };

  static const _user2 = {
    'id': 'user-2',
    'displayName': 'Ama Owusu',
    'username': 'ama',
    'status': 'suspended',
    'createdAt': '2026-10-02T10:00:00.000Z',
    'groups': [
      {'id': 'g-riders', 'name': 'Riders', 'role': 'passenger'},
    ],
    'roles': ['passenger'],
  };

  Future<void> _handle(HttpRequest request) async {
    requests.add('${request.method} ${request.uri}');
    authorization.add(request.headers.value(HttpHeaders.authorizationHeader));
    actionHeaders.add(request.headers.value('x-admin-action'));
    final path = request.uri.path;
    final payload = utf8.decode(
      await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
    );
    Object body;
    var status = HttpStatus.ok;
    if (forbiddenStatus != 0) {
      status = forbiddenStatus;
      body = {
        'error': {
          'code': 'forbidden',
          'message': 'Your groups do not grant users:read.',
        },
      };
    } else if (path == '/v1/auth/admin-action-token') {
      final password = payload.isEmpty
          ? null
          : (jsonDecode(payload) as Map)['password'];
      if (password == 'secret') {
        tokenCounter++;
        body = {
          'data': {
            'token': 'action-token-$tokenCounter',
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 5))
                .toUtc()
                .toIso8601String(),
          },
        };
      } else {
        status = HttpStatus.unauthorized;
        body = {
          'error': {
            'code': 'unauthorized',
            'message': 'Incorrect password or PIN.',
          },
        };
      }
    } else if (request.method != 'GET' && rejectActionTokens > 0) {
      rejectActionTokens--;
      status = HttpStatus.forbidden;
      body = {
        'error': {
          'code': 'admin_action_required',
          'message': 'Confirm this action with your password or PIN.',
        },
      };
    } else if (path == '/v1/admin/summary') {
      body = {
        'data': {
          'users': {'active': 11, 'pending': 2},
          'trips': {'open': 4},
          'bookings': {'requested': 3},
          'groups': {'total': 8},
        },
      };
    } else if (path == '/v1/admin/users' && request.method == 'GET') {
      final pendingOnly = request.uri.queryParameters['status'] == 'pending';
      body = {
        'data': pendingOnly ? <Object>[] : [_user, if (twoUsers) _user2],
        'total': pendingOnly ? 0 : (twoUsers ? 2 : 1),
      };
    } else if (path.startsWith('/v1/admin/users/') &&
        request.method == 'PATCH') {
      body = {'data': _user};
    } else if (path == '/v1/admin/groups') {
      body = {
        'data': [
          {
            'id': 'g-riders',
            'name': 'Riders',
            'role': 'passenger',
            'description': 'Everyone who books seats.',
            'isSystem': true,
            'memberCount': 9,
            'permissions': <String>[],
          },
        ],
      };
    } else if (path == '/v1/admin/trips') {
      body = {'data': <Object>[], 'total': 0};
    } else if (path == '/v1/admin/bookings') {
      body = {
        'data': <Object>[],
        'total': 0,
        'totals': {
          'bookings': 0,
          'requested': 0,
          'confirmed': 0,
          'cancelled': 0,
          'seats': 0,
          'fare': 0,
        },
      };
    } else {
      status = HttpStatus.notFound;
      body = {
        'error': {'code': 'not_found', 'message': 'Route not found.'},
      };
    }
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }
}

LocalAuthSession _session({
  String role = 'admin',
  List<String> permissions = const [],
}) => LocalAuthSession(
  accessToken: 'token-123',
  role: role,
  displayName: 'Test Admin',
  userId: 'me',
  roles: [role],
  permissions: permissions,
);

Future<void> _settle(WidgetTester tester) async {
  // Real socket I/O only completes outside the fake-async test zone, and each
  // hop of a request (connect, send, receive, decode) resumes only when the
  // fake zone's microtasks are flushed, so alternate the two a few times.
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

/// Steps animations forward without `pumpAndSettle`, which would advance fake
/// time past the client's request timeouts while real socket I/O is in flight.
Future<void> _animate(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Runs [body] against a fake admin server, then unmounts the tree and closes
/// the client and server so no socket timers outlive the test.
Future<void> _withAdmin(
  WidgetTester tester,
  Future<void> Function(_FakeAdminServer server, AdminApiClient client) body, {
  List<String?> credentials = const ['secret'],
}) async {
  final server = (await tester.runAsync(_FakeAdminServer.start))!;
  final queue = [...credentials];
  final client = AdminApiClient(
    baseUrl: server.baseUrl,
    accessToken: 'token-123',
    promptCredential: ({String? error}) async =>
        queue.isEmpty ? null : queue.removeAt(0),
  );
  try {
    await body(server, client);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
    await tester.runAsync(server.close);
  }
}

Finder _tooltip(String message) => find.byTooltip(message);

void main() {
  setUp(() => HttpOverrides.global = null);

  group('AdminApiClient', () {
    test('sends the bearer token, encodes filters and parses users', () async {
      final server = await _FakeAdminServer.start();
      final client = AdminApiClient(
        baseUrl: server.baseUrl,
        accessToken: 'token-123',
      );
      try {
        final page = await client.listUsers(
          search: 'ko fi',
          status: 'active',
          limit: 20,
        );
        expect(page.total, 1);
        expect(page.items.single.displayName, 'Kofi Mensah');
        expect(page.items.single.handle, '@kofi');
        expect(page.items.single.groups.single.name, 'Riders');
        expect(server.authorization.single, 'Bearer token-123');
        expect(
          server.actionHeaders.single,
          isNull,
          reason: 'reads never carry an admin-action token',
        );
        final uri = Uri.parse(server.requests.single.split(' ').last);
        expect(uri.path, '/v1/admin/users');
        expect(uri.queryParameters, {
          'search': 'ko fi',
          'status': 'active',
          'limit': '20',
          'offset': '0',
        });
      } finally {
        client.dispose();
        await server.close();
      }
    });

    test('surfaces the server message and marks forbidden responses', () async {
      final server = await _FakeAdminServer.start();
      server.forbiddenStatus = HttpStatus.forbidden;
      final client = AdminApiClient(
        baseUrl: server.baseUrl,
        accessToken: 'token-123',
      );
      try {
        await expectLater(
          client.listUsers(),
          throwsA(
            isA<AdminApiException>()
                .having(
                  (error) => error.message,
                  'message',
                  'Your groups do not grant users:read.',
                )
                .having((error) => error.isForbidden, 'isForbidden', true),
          ),
        );
      } finally {
        client.dispose();
        await server.close();
      }
    });

    test('reports an unreachable server without leaking details', () async {
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close(force: true);
      final client = AdminApiClient(
        baseUrl: 'http://127.0.0.1:$port',
        accessToken: 'token-123',
      );
      try {
        await expectLater(
          client.dashboard(),
          throwsA(
            isA<AdminApiException>().having(
              (error) => error.status,
              'status',
              0,
            ),
          ),
        );
      } finally {
        client.dispose();
      }
    });

    test(
      'a write prompts once for the password, sends the action token and reuses it',
      () async {
        final server = await _FakeAdminServer.start();
        var prompts = 0;
        final client = AdminApiClient(
          baseUrl: server.baseUrl,
          accessToken: 'token-123',
          promptCredential: ({String? error}) async {
            prompts++;
            return 'secret';
          },
        );
        try {
          await client.updateUser('user-1', displayName: 'A');
          await client.updateUser('user-1', displayName: 'B');
          expect(
            prompts,
            1,
            reason: 'the token is reused until it nears expiry',
          );
          final writes = [
            for (var i = 0; i < server.requests.length; i++)
              if (server.requests[i].startsWith('PATCH'))
                server.actionHeaders[i],
          ];
          expect(writes, ['action-token-1', 'action-token-1']);
          // The password itself is only ever sent to the token endpoint.
          expect(
            server.requests
                .where((request) => request.contains('admin-action-token'))
                .length,
            1,
          );
        } finally {
          client.dispose();
          await server.close();
        }
      },
    );

    test(
      'a wrong password asks again with the server message; cancelling sends nothing',
      () async {
        final server = await _FakeAdminServer.start();
        final errors = <String?>[];
        final answers = <String?>['wrong', 'secret'];
        final client = AdminApiClient(
          baseUrl: server.baseUrl,
          accessToken: 'token-123',
          promptCredential: ({String? error}) async {
            errors.add(error);
            return answers.removeAt(0);
          },
        );
        try {
          await client.updateUser('user-1', displayName: 'A');
          expect(errors, [null, 'Incorrect password or PIN.']);
        } finally {
          client.dispose();
        }

        final cancelling = AdminApiClient(
          baseUrl: server.baseUrl,
          accessToken: 'token-123',
          promptCredential: ({String? error}) async => null,
        );
        try {
          final before = server.requests.length;
          await expectLater(
            cancelling.updateUser('user-1', displayName: 'B'),
            throwsA(
              isA<AdminApiException>().having(
                (error) => error.cancelled,
                'cancelled',
                true,
              ),
            ),
          );
          expect(
            server.requests.length,
            before,
            reason: 'nothing is sent when the prompt is dismissed',
          );
        } finally {
          cancelling.dispose();
          await server.close();
        }
      },
    );

    test(
      'an expired action token is renewed once and the write retried',
      () async {
        final server = await _FakeAdminServer.start();
        var prompts = 0;
        final client = AdminApiClient(
          baseUrl: server.baseUrl,
          accessToken: 'token-123',
          promptCredential: ({String? error}) async {
            prompts++;
            return 'secret';
          },
        );
        try {
          await client.updateUser(
            'user-1',
            displayName: 'A',
          ); // obtains token 1
          server.rejectActionTokens = 1; // server now says the token is no good
          await client.updateUser('user-1', displayName: 'B');
          expect(prompts, 2);
          expect(server.actionHeaders.last, 'action-token-2');
        } finally {
          client.dispose();
          await server.close();
        }
      },
    );

    test('writes fail clearly when no prompt is available', () async {
      final server = await _FakeAdminServer.start();
      final client = AdminApiClient(
        baseUrl: server.baseUrl,
        accessToken: 'token-123',
      );
      try {
        await expectLater(
          client.deleteUser('user-1'),
          throwsA(isA<AdminApiException>()),
        );
        expect(server.requests, isEmpty);
      } finally {
        client.dispose();
        await server.close();
      }
    });
  });

  test('only accounts whose groups hold admin:access get the Admin menu', () {
    expect(
      _session(
        permissions: const ['admin:access', 'users:read'],
      ).hasAdminAccess,
      isTrue,
    );
    expect(
      _session(permissions: const ['users:read', 'trips:read']).hasAdminAccess,
      isFalse,
      reason: 'scope without admin:access',
    );
    expect(
      _session(permissions: const ['users:read']).can('users:read'),
      isTrue,
    );
    expect(
      _session(permissions: const ['users:read']).can('users:create'),
      isFalse,
    );
    expect(_session().hasAdminAccess, isFalse);
    expect(_session(role: 'operator').isStaff, isTrue);
    expect(_session(role: 'driver').isStaff, isFalse);
    expect(_session(role: 'passenger').isStaff, isFalse);
  });

  group('booking CSV', () {
    final row = AdminBookingRow(
      id: 'r-1',
      seats: 2,
      status: 'requested',
      fare: 40,
      createdAt: DateTime(2026, 10, 1, 9, 5),
      tripId: 't-1',
      from: 'Kasoa',
      to: 'Circle, Accra',
      pickupJunction: 'Kasoa "Market"',
      departureAt: DateTime(2026, 10, 4, 7, 30),
      tripStatus: 'open',
      isWomenOnly: false,
      passengerName: '=HYPERLINK("http://evil")',
      passengerUsername: 'ama',
      driverName: 'Kofi',
    );

    test('escapes delimiters and neutralizes spreadsheet formulas', () {
      final csv = bookingsToCsv([row]).split('\r\n');
      expect(
        csv.first,
        startsWith(
          'No.,Rider,Username,Driver,Date,Time,From,To,Pickup,Seats,Fare (GHS),Status',
        ),
      );
      expect(
        csv[1],
        contains('"\'=HYPERLINK(""http://evil"")"'),
        reason: 'formula is prefixed with an apostrophe and quoted',
      );
      expect(csv[1], contains('"Circle, Accra"'));
      expect(csv[1], contains('"Kasoa ""Market"""'));
      expect(csv[1], contains('2026-10-04,07:30'));
      expect(csv[1], contains(',Pending,'));
    });

    test('csvField leaves plain text alone', () {
      expect(csvField('Madina'), 'Madina');
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('-5'), "'-5");
      expect(csvField(''), '');
    });
  });

  Widget adminHome(AdminApiClient client, LocalAuthSession session) =>
      MaterialApp(
        home: Scaffold(
          body: AdminScreen(client: client, session: session),
        ),
      );

  testWidgets(
    'Admin shows only the sections, sub-tabs and action pills the account is permitted to use',
    (tester) async {
      await _withAdmin(tester, (server, client) async {
        await tester.pumpWidget(
          adminHome(
            client,
            _session(
              permissions: const [
                'dashboard:read',
                'users:read',
                'groups:read',
              ],
            ),
          ),
        );
        await _settle(tester);

        expect(find.text('Admin dashboard'), findsOneWidget);
        // Primary pills on the dark strip, then Onboard-style sub-tab pills.
        expect(find.text('People'), findsOneWidget);
        expect(find.text('Operations'), findsNothing);
        expect(find.text('Users'), findsOneWidget);
        expect(find.text('Groups'), findsWidgets);
        // Action pills.
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('Reports'), findsNothing);
        expect(find.text('Audit'), findsNothing);
        // Summary tiles reflect what the account may see.
        expect(find.text('Members'), findsOneWidget);
        expect(find.text('11'), findsOneWidget);
        expect(find.text('Open trips'), findsNothing);
        // Without users:approve there is no pending alert even though 2 are waiting.
        expect(find.textContaining('awaiting approval'), findsNothing);
        // The first sub-tab is already showing its table.
        expect(find.text('Kofi Mensah'), findsOneWidget);
        expect(
          find.text('FULL NAME'),
          findsOneWidget,
          reason: 'users are shown as a compact table',
        );
        expect(
          find.text('Manage Users'),
          findsNothing,
          reason: 'users:create is not held',
        );
      });
    },
  );

  testWidgets('the Groups sub-tab and the summary tiles switch tabs', (
    tester,
  ) async {
    await _withAdmin(tester, (server, client) async {
      await tester.pumpWidget(
        adminHome(
          client,
          _session(permissions: const ['users:read', 'groups:read']),
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Groups').last);
      await _animate(tester);
      await _settle(tester);
      expect(find.text('Everyone who books seats.'), findsOneWidget);
      expect(find.text('New group'), findsNothing);

      // Tapping the Members tile returns to Users.
      await tester.tap(find.text('Members'));
      await _animate(tester);
      await _settle(tester);
      expect(find.text('Kofi Mensah'), findsOneWidget);
    });
  });

  testWidgets(
    'a pending-approval alert appears for accounts that can approve',
    (tester) async {
      await _withAdmin(tester, (server, client) async {
        await tester.pumpWidget(
          adminHome(
            client,
            _session(permissions: const ['users:read', 'users:approve']),
          ),
        );
        await _settle(tester);
        expect(find.text('2 accounts awaiting approval'), findsOneWidget);
        expect(find.text('Review'), findsOneWidget);
      });
    },
  );

  testWidgets(
    'bulk suspend asks for confirmation, then the password, then applies with the action token',
    (tester) async {
      await _withAdmin(tester, (server, client) async {
        await tester.pumpWidget(
          adminHome(
            client,
            _session(permissions: const ['users:read', 'users:manage_status']),
          ),
        );
        await _settle(tester);

        await tester.tap(find.text('Select all'));
        await tester.pump();
        expect(find.text('1 selected'), findsOneWidget);
        await tester.tap(find.text('Actions'));
        await _animate(tester);
        await tester.tap(find.text('Suspend selected'));
        await _animate(tester);
        expect(find.text('Suspend 1 person?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
        await _animate(tester);
        await _settle(tester);

        final patchIndex = server.requests.indexWhere(
          (request) => request.startsWith('PATCH /v1/admin/users/user-1'),
        );
        expect(patchIndex, greaterThanOrEqualTo(0));
        expect(server.actionHeaders[patchIndex], 'action-token-1');
        expect(find.textContaining('1 of 1 done'), findsOneWidget);
      });
    },
  );

  group('compact users table', () {
    testWidgets(
      'rows are 32 px, sorting toggles on the header and users:create shows Manage Users',
      (tester) async {
        await _withAdmin(tester, (server, client) async {
          server.twoUsers = true;
          await tester.pumpWidget(
            adminHome(
              client,
              _session(permissions: const ['users:read', 'users:create']),
            ),
          );
          await _settle(tester);

          expect(find.text('Manage Users'), findsOneWidget);
          // Compact rows: two people sit exactly one row height apart.
          final ama = tester.getTopLeft(find.text('Ama Owusu')).dy;
          final kofi = tester.getTopLeft(find.text('Kofi Mensah')).dy;
          expect(
            ama,
            lessThan(kofi),
            reason: 'sorted by full name ascending by default',
          );
          expect(kofi - ama, closeTo(32, 0.01));

          await tester.tap(find.text('FULL NAME'));
          await tester.pump();
          expect(
            tester.getTopLeft(find.text('Kofi Mensah')).dy,
            lessThan(tester.getTopLeft(find.text('Ama Owusu')).dy),
          );
        });
      },
    );

    testWidgets('dragging a header edge resizes that column', (tester) async {
      await _withAdmin(tester, (server, client) async {
        await tester.pumpWidget(
          adminHome(client, _session(permissions: const ['users:read'])),
        );
        await _settle(tester);

        final before = tester.getTopLeft(find.text('FULL NAME')).dx;
        final y = tester.getCenter(find.text('FULL NAME')).dy;
        // The handle straddles the boundary between USERNAME and FULL NAME.
        await tester.dragFrom(Offset(before - 6 - 6, y), const Offset(40, 0));
        await tester.pump();
        expect(
          tester.getTopLeft(find.text('FULL NAME')).dx,
          closeTo(before + 40, 1),
        );
      });
    });

    testWidgets(
      'uses the exact Onboard column names and shows each person\'s groups',
      (tester) async {
        await _withAdmin(tester, (server, client) async {
          await tester.pumpWidget(
            adminHome(client, _session(permissions: const ['users:read'])),
          );
          await _settle(tester);

          for (final label in [
            'USERNAME',
            'FULL NAME',
            'GROUPS',
            'TEL',
            'SUBURB',
            'STATUS',
            'ROLE',
          ]) {
            expect(find.text(label), findsOneWidget, reason: label);
          }
          for (final gone in ['NAME', 'HOME AREA', 'PHONE', 'JOINED']) {
            expect(find.text(gone), findsNothing, reason: gone);
          }
          expect(
            find.text('Riders'),
            findsOneWidget,
            reason: 'the GROUPS cell lists the groups the user belongs to',
          );
          expect(find.text('Rider'), findsOneWidget, reason: 'ROLE column');
          expect(find.text('ACTIVE'), findsOneWidget);
          expect(
            find.text('Manage Users'),
            findsNothing,
            reason: 'read-only accounts get no Manage button',
          );
        });
      },
    );

    testWidgets(
      'Manage Users lists only permitted actions and Modify asks who, then edits',
      (tester) async {
        await _withAdmin(tester, (server, client) async {
          await tester.pumpWidget(
            adminHome(
              client,
              _session(
                permissions: const [
                  'users:read',
                  'users:update',
                  'users:manage_status',
                ],
              ),
            ),
          );
          await _settle(tester);

          await tester.tap(find.text('Manage Users'));
          await _animate(tester);
          expect(
            find.text(
              'Choose an action. You will select the users before it runs.',
            ),
            findsOneWidget,
          );
          expect(find.text('Modify User'), findsOneWidget);
          expect(find.text('Disable / Suspend User'), findsOneWidget);
          expect(find.text('Enable / Activate User'), findsOneWidget);
          expect(
            find.text('Add New User'),
            findsNothing,
            reason: 'users:create is not held',
          );
          expect(find.text('Reset Password'), findsNothing);
          expect(find.text('Delete User'), findsNothing);

          await tester.tap(find.text('Modify User'));
          await _animate(tester);
          expect(find.text('Select one user to modify'), findsOneWidget);
          await tester.tap(find.text('Kofi Mensah').last);
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Modify user'));
          await _animate(tester);
          expect(find.text('Edit details'), findsOneWidget);
          await tester.enterText(
            find.widgetWithText(TextField, 'Full name'),
            'Kofi A. Mensah',
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await _animate(tester);
          await _settle(tester);

          final patch = server.requests.indexWhere(
            (request) => request.startsWith('PATCH /v1/admin/users/user-1'),
          );
          expect(patch, greaterThanOrEqualTo(0));
          expect(server.actionHeaders[patch], 'action-token-1');
        });
      },
    );

    testWidgets(
      'the toolbar fits a phone screen with every row ticked (no overflow)',
      (tester) async {
        tester.view.physicalSize = const Size(411, 890);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _withAdmin(tester, (server, client) async {
          server.twoUsers = true;
          await tester.pumpWidget(
            adminHome(
              client,
              _session(
                permissions: const [
                  'users:read',
                  'users:create',
                  'users:update',
                  'users:manage_status',
                  'users:reset_credentials',
                  'users:delete',
                  'groups:read',
                  'groups:create',
                  'groups:delete',
                ],
              ),
            ),
          );
          await _settle(tester);

          await tester.tap(find.text('Select all'));
          await tester.pump();
          expect(find.text('2 sel.'), findsOneWidget);
          expect(find.text('Clear'), findsOneWidget);
          expect(find.text('Manage'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: 'no RenderFlex overflow',
          );

          await tester.tap(find.text('Groups').first);
          await _animate(tester);
          await _settle(tester);
          await tester.tap(find.text('Select all'));
          await tester.pump();
          expect(find.text('1 sel.'), findsOneWidget);
          expect(find.text('New'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: 'no RenderFlex overflow',
          );
        });
      },
    );

    testWidgets('long press opens a row menu with permitted actions only', (
      tester,
    ) async {
      await _withAdmin(tester, (server, client) async {
        await tester.pumpWidget(
          adminHome(
            client,
            _session(permissions: const ['users:read', 'users:manage_status']),
          ),
        );
        await _settle(tester);

        await tester.longPress(find.text('Kofi Mensah'));
        await _animate(tester);
        expect(find.text('Suspend'), findsOneWidget);
        expect(
          find.text('Modify'),
          findsNothing,
          reason: 'users:update is not held',
        );
        expect(find.text('Reset Password'), findsNothing);
        expect(
          find.text('Delete'),
          findsNothing,
          reason: 'users:delete is not held',
        );
      });
    });
  });

  group('sign out', () {
    Future<void> pumpWithScope(
      WidgetTester tester,
      Widget home, {
      required List<int> calls,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => SignOutScope(
            onSignOut: () async => calls.add(calls.length + 1),
            child: child!,
          ),
          home: home,
        ),
      );
    }

    testWidgets('Admin offers a confirmed sign out', (tester) async {
      final calls = <int>[];
      await _withAdmin(tester, (server, client) async {
        await pumpWithScope(
          tester,
          Scaffold(
            body: AdminScreen(
              client: client,
              session: _session(permissions: const ['users:read']),
            ),
          ),
          calls: calls,
        );
        await _settle(tester);

        await tester.tap(_tooltip('Sign out'));
        await _animate(tester);
        expect(find.text('Sign out?'), findsOneWidget);
        await tester.tap(find.text('Stay signed in'));
        await _animate(tester);
        expect(
          calls,
          isEmpty,
          reason: 'declining the confirmation keeps the session',
        );

        await tester.tap(_tooltip('Sign out'));
        await _animate(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
        await _animate(tester);
        expect(calls, [1]);
      });
    });

    testWidgets(
      'pushed admin pages and every bottom tab carry the same control',
      (tester) async {
        final calls = <int>[];
        await _withAdmin(tester, (server, client) async {
          await pumpWithScope(
            tester,
            Scaffold(
              body: AdminScreen(
                client: client,
                session: _session(
                  permissions: const ['users:read', 'reports:read'],
                ),
              ),
            ),
            calls: calls,
          );
          await _settle(tester);
          await tester.tap(find.text('Reports'));
          await _animate(tester);
          await _settle(tester);
          // Reports is a pushed route with its own back arrow and sign-out.
          expect(_tooltip('Back'), findsOneWidget);
          expect(_tooltip('Sign out'), findsOneWidget);
          await tester.tap(_tooltip('Sign out'));
          await _animate(tester);
          expect(find.text('Sign out?'), findsOneWidget);
          await tester.tap(find.text('Stay signed in'));
          await _animate(tester);
        });

        final repository = InMemoryTripRepository();
        await repository.initialize();
        await pumpWithScope(
          tester,
          YenkoRootScreen(
            repository: repository,
            session: _session(role: 'passenger'),
          ),
          calls: calls,
        );
        await tester.pump();
        expect(_tooltip('Sign out'), findsWidgets);
        // Passengers no longer get an Offer tab (see yenko_root_screen.dart).
        for (final tab in ['Rides', 'Messages', 'Profile']) {
          await tester.tap(find.text(tab).last);
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            _tooltip('Sign out'),
            findsWidgets,
            reason: '$tab has a sign-out button',
          );
        }
      },
    );

    testWidgets('there is no sign-out control outside a signed-in session', (
      tester,
    ) async {
      final repository = InMemoryTripRepository();
      await repository.initialize();
      await tester.pumpWidget(
        MaterialApp(home: YenkoRootScreen(repository: repository)),
      );
      await tester.pump();
      expect(_tooltip('Sign out'), findsNothing);
    });
  });

  testWidgets(
    'an account with no admin permissions sees an explanation, not an empty screen',
    (tester) async {
      await _withAdmin(tester, (server, client) async {
        await tester.pumpWidget(adminHome(client, _session()));
        await tester.pump();
        expect(find.text('No admin access'), findsOneWidget);
        expect(server.requests, isEmpty);
      });
    },
  );

  testWidgets(
    'admins keep the regular tabs and get Admin as the last bottom-navigation option',
    (tester) async {
      final repository = InMemoryTripRepository();
      await repository.initialize();
      await _withAdmin(tester, (server, client) async {
        await tester.pumpWidget(
          MaterialApp(
            home: YenkoRootScreen(
              repository: repository,
              session: _session(
                role: 'super_admin',
                permissions: const ['dashboard:read', 'users:read'],
              ),
              adminClient: client,
            ),
          ),
        );
        await tester.pump();

        // super_admin is not the 'driver' role, so no Offer tab — only
        // drivers get a dedicated Offer tab (see yenko_root_screen.dart).
        final labels = ['Home', 'Rides', 'Messages', 'Profile', 'Admin'];
        final xs = [
          for (final label in labels)
            tester.getCenter(find.text(label).last).dx,
        ];
        expect(
          xs,
          orderedEquals([...xs]..sort()),
          reason: 'Admin sits at the end of the bar',
        );

        await tester.tap(find.text('Admin').last);
        await _settle(tester);
        expect(find.text('Admin dashboard'), findsOneWidget);
        expect(find.text('People'), findsOneWidget);
        expect(find.text('Kofi Mensah'), findsOneWidget);
      });
    },
  );

  testWidgets('riders keep the familiar tabs and get no admin tab', (
    tester,
  ) async {
    final repository = InMemoryTripRepository();
    await repository.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: YenkoRootScreen(
          repository: repository,
          session: _session(role: 'passenger'),
        ),
      ),
    );
    await tester.pump();
    // Passengers see search/discovery tabs but no Offer tab — posting a ride
    // is a driver-only action (see yenko_root_screen.dart).
    for (final label in ['Home', 'Rides', 'Messages', 'Profile']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Offer'), findsNothing);
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('drivers get a dashboard home tab and keep the Offer tab', (
    tester,
  ) async {
    final repository = InMemoryTripRepository();
    await repository.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: YenkoRootScreen(
          repository: repository,
          session: _session(role: 'driver'),
        ),
      ),
    );
    await tester.pump();
    for (final label in ['Home', 'Offer', 'Rides', 'Messages', 'Profile']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Admin'), findsNothing);
    expect(find.textContaining('Hello, Test'), findsOneWidget);
  });

  testWidgets(
    'a driver can accept or decline a pending seat request from the dashboard',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = InMemoryTripRepository();
      await repository.initialize();
      await repository.postTrip(
        from: 'East Legon',
        to: 'Circle',
        pickupJunction: '37 Station',
        seats: 2,
        pricePerSeat: 20,
        womenOnly: false,
      );
      await repository.requestSeat(repository.trips.first);

      await tester.pumpWidget(
        MaterialApp(
          home: YenkoRootScreen(
            repository: repository,
            session: _session(role: 'driver'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Seat requests'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      await tester.ensureVisible(find.text('Accept'));
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(find.text('Seat requests'), findsNothing);
      expect(repository.bookings.single.status, 'confirmed');
    },
  );

  testWidgets(
    'a driver can confirm receiving a direct mobile money payment from the dashboard',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = InMemoryTripRepository();
      await repository.initialize();
      await repository.setMomoDetails(
        momoNumber: '+233244000111',
        momoNetwork: 'mtn',
      );
      await repository.postTrip(
        from: 'East Legon',
        to: 'Circle',
        pickupJunction: '37 Station',
        seats: 2,
        pricePerSeat: 20,
        womenOnly: false,
      );
      await repository.requestSeat(repository.trips.first);
      await repository.confirmReservation(
        repository.pendingDriverReservations.single,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: YenkoRootScreen(
            repository: repository,
            session: _session(role: 'driver'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Payments to confirm'), findsOneWidget);
      expect(find.text("I've received this payment"), findsOneWidget);

      await tester.ensureVisible(find.text("I've received this payment"));
      await tester.tap(find.text("I've received this payment"));
      await tester.pumpAndSettle();

      expect(find.text('Payments to confirm'), findsNothing);
      expect(
        repository.bookings.single.paymentStatus,
        'driver_confirmed_received',
      );
    },
  );
}
