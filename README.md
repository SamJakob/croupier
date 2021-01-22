# Croupier
A custom SocketCluster client implementation for Dart and Flutter.

![Run Tests](https://github.com/SamJakob/croupier/workflows/Run%20Tests/badge.svg) ![MIT License](https://img.shields.io/github/license/SamJakob/croupier) ![GitHub issues](https://img.shields.io/github/issues/SamJakob/croupier)

Released under an [MIT license][license]. 
Feel free to use or adapt this code as you want, though if you do,
please credit me your README or something.

## Usage
A simple usage example:

```dart
import 'package:croupier/croupier.dart';

void main() async {
  
  // Create the client.
  var client = SocketClusterClient(
    hostname: 'localhost',
    port: 3000,
    ackTimeout: 500,
  );
  
  // Connect to the server.
  await client.connect();
  
  // Use the client; (invokes 'myProcedure' on the server.)
  var response = await client.invoke('myProcedure');
  print(response);
  
  // Close the client to clean up resources and
  // cleanly disconnect from the server.
  await client.close();
  
}
```

For more examples, please see the [project wiki][wiki].

## Features and bugs
Please file feature requests and bugs at the [issue tracker][tracker].

## Test
Unit tests are included.  
Run `dart pub run test` to execute the unit tests.

[license]: https://github.com/SamJakob/croupier/blob/master/LICENSE
[tracker]: https://github.com/SamJakob/croupier/issues
[wiki]: https://github.com/SamJakob/croupier/wiki