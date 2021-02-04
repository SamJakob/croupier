import 'dart:async';

import 'package:croupier/croupier.dart';
import 'package:test/test.dart';

void main() {
  group('Smoke test', () {
    test('All events have names defined', () {
      var definedNames = [];

      for (var event in SCEvent.values) {
        if (event.name == null) {
          fail('$event does not have a unique event name defined.');
        }

        if (definedNames.contains(event.name)) {
          fail("$event's name has already been defined!");
        }

        definedNames.add(event.name);
      }
    });
  });

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
    });

    test('Client closes after implicit connect call', () async {
      await client.close();

      expect(client.authState, equals(AuthenticationState.UNAUTHENTICATED));
      expect(client.state, equals(ConnectionState.CLOSED));
    });
  });

  group('Remote Procedure Calls (RPC)', () {
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

  group('Local Procedure Calls (Server -> Client)', () {
    SocketClusterClient client;

    setUpAll(() async {
      client = SocketClusterClient(
        hostname: 'localhost',
        port: 3000,
        ackTimeout: 500,
      );
    });

    test('Local receive', () async {
      var completer = Completer();

      client.registerReceiver(
        'testRecv',
        (data) => {
          completer.complete(data['data']),
        },
      );

      client.transmit('triggerTestRecv');

      expect(completer.future,
          completion(equals('4aa78d81f5ff8f60de71c42c86a80b36')));
    });

    test('Local invoke', () {
      var completer = Completer();

      client.registerReceiver(
        'testInvkResult',
        (data) => {
          completer.complete(data['data']),
        },
      );

      client.registerProcedure('testInvk', (data) {
        print('hello from the other side');
        return 'hello from the other side';
      });

      client.transmit('triggerTestInvk');
      expect(completer.future, completion(equals('hello from the other side')));
    });

    tearDownAll(() async {
      await client.close();
    });
  });

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

  group('Housekeeping', () {
    test('Signal end of tests to server...', () async {
      var client = SocketClusterClient(
        hostname: 'localhost',
        port: 3000,
        ackTimeout: 500,
      );

      client.transmit('testFinish');
      await client.close();

      print('All done!');
    });
  });
}
