import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yenko_app/core/data/local_auth_client.dart';

void main() {
  test(
    'logs in and returns the access token, role, and display name',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = http.Client();
      try {
        server.listen((request) async {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          expect(body['identity'], '+233200000001');
          expect(body['password'], '6930');
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'data': {
                  'accessToken': 'test-token',
                  'mustChangePin': false,
                  'user': {
                    'id': 'demo-driver-kwame',
                    'displayName': 'Kwame Mensah',
                    'role': 'driver',
                  },
                },
              }),
            );
          await request.response.close();
        });

        final authClient = LocalAuthClient(
          baseUrl:
              'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
          client: client,
        );
        final session = await authClient.login(
          identity: '+233200000001',
          password: '6930',
        );

        expect(session.accessToken, 'test-token');
        expect(session.role, 'driver');
        expect(session.displayName, 'Kwame Mensah');
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );

  test('surfaces the server error message on failed login', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = http.Client();
    try {
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'error': {
                'code': 'unauthorized',
                'message': 'Incorrect phone/username or PIN.',
              },
            }),
          );
        await request.response.close();
      });

      final authClient = LocalAuthClient(
        baseUrl:
            'http://${InternetAddress.loopbackIPv4.address}:${server.port}',
        client: client,
      );

      await expectLater(
        authClient.login(identity: '+233200000001', password: 'wrong'),
        throwsA(
          isA<LocalAuthException>().having(
            (error) => error.message,
            'message',
            'Incorrect phone/username or PIN.',
          ),
        ),
      );
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
}
