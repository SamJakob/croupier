A custom SocketCluster client implementation for Dart and Flutter.

Released under an MIT [license](./LICENSE). 
Feel free to use or adapt this code as you want, though if you do,
please credit me your README or something.

## Usage

A simple usage example:

```dart
import 'package:croupier/croupier.dart';

main() async {
  
  // Create the client.
  SocketClusterClient client = SocketClusterClient(
    hostname: 'localhost',
    port: 3000,
    ackTimeout: 500,
  );
  
  // Connect to the server.
  await client.connect();
  
  // Close the client to clean up resources and
  // cleanly disconnect from the server.
  await client.close();
  
}
```

## Test
Unit tests are included.  
Run `dart pub run test` to execute the unit tests.

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: http://example.com/issues/replaceme
