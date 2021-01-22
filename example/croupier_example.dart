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
