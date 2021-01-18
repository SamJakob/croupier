import 'dart:async';

import 'package:croupier/croupier.dart';
import 'package:test/test.dart';

void main() {
  group('Basic tests', () {
    SocketClusterClient client;

    setUpAll(() {
      client = SocketClusterClient(
        hostname: 'localhost',
        port: 3000,
        ackTimeout: 500,
      );
    });

    test('Client connects explicitly', () {
      expect(client.connect(), completion(isNull));
    });

    test('Client cannot be connected multiple times', () {
      expect(client.connect(), throwsStateError);
    });

    test('Client closes after explicit connect call', () async {
      await client.close();

      expect(client.authState, equals(AuthenticationState.UNAUTHENTICATED));
      expect(client.state, equals(ConnectionState.CLOSED));
    });

    test('Client connects implicitly', () {
      expect(client.invoke('unknownProc'),
          throwsA(TypeMatcher<TimeoutException>()));
    });

    test('Client reconnects', () async {
      print('Sending shutdown command...');
      client.transmit('shutdown');

      print('Delaying 200ms to allow server shutdown.');
      await Future.delayed(Duration(milliseconds: 200));

      print('Done!');
      print('Please restart server to continue unit tests.');
    });

    test('Client closes after implicit connect call', () async {
      await client.close();

      expect(client.authState, equals(AuthenticationState.UNAUTHENTICATED));
      expect(client.state, equals(ConnectionState.CLOSED));
    });
  });

  group('Procedure calls', () {
    SocketClusterClient client;

    setUpAll(() {
      client = SocketClusterClient(
        hostname: 'localhost',
        port: 3000,
        ackTimeout: 500,
      );
    });

    test('Good procedure call', () {
      expect(client.invoke('customProc'), completion(equals('Success')));
    });

    test('Bad procedure call', () async {
      try {
        await client.invoke('customProc', {'bad': true});
        fail("Bad procedure call didn't throw an exception.");
      } catch (ex) {
        expect(ex, TypeMatcher<SocketMessageError>());
        expect(ex.name, equals('BadCustomError'));
        expect(ex.message, equals('Server failed to execute the procedure'));
      }
    });

    test('Unknown procedure call', () {
      expect(client.invoke('unknownProc'),
          throwsA(TypeMatcher<TimeoutException>()));
    });

    tearDownAll(() async {
      await client.close();
    });
  });

  group('Transmit calls', () {});

  group('Raw data', () {
    SocketClusterClient client;

    setUpAll(() async {
      client = SocketClusterClient(
        hostname: 'localhost',
        port: 3000,
        ackTimeout: 500,
      );

      await client.connect();
    });

    test('Raw data', () {
      client.send('hello');
    });

    tearDownAll(() async {
      await client.close();
    });
  });
}
