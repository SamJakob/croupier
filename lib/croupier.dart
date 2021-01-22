/// A custom SocketCluster client implementation for Dart and Flutter.
library croupier;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';

part 'src/multiplexed_stream.dart';
part 'src/croupier_reconnect_policy.dart';
part 'src/croupier_impl.dart';

enum ConnectionState {
  CLOSED,
  CONNECTING,
  OPEN,
}

enum AuthenticationState {
  UNAUTHENTICATED,
  AUTHENTICATED,
}

enum SCEvent {
  /// Emitted whenever the socket initiates a connection to the server. This
  /// includes reconnects.
  CONNECTING,

  /// Emitted whenever the socket disconnects or becomes disconnected from the
  /// server. One can read the [SocketClusterClient.closeCode] and the
  /// [SocketClusterClient.closeReason] from the socket to determine the close
  /// code and reason.
  DISCONNECT,

  /// Emitted when the socket is programmatically closed with a call to
  /// [SocketClusterClient.close]. This is triggered right before the socket
  /// closes unlike [SCEvent.DISCONNECT] which is triggered right after the
  /// close is processed.
  CLOSE,

  /// Emitted whenever the authentication state changes. The new authentication
  /// state may be read from [SocketClusterClient.authState].
  AUTH_STATE_CHANGE,
}

extension SCEventName on SCEvent {
  String get name {
    switch (this) {
      case SCEvent.CONNECTING:
        return 'connecting';
      case SCEvent.DISCONNECT:
        return 'disconnect';
      case SCEvent.CLOSE:
        return 'close';
      case SCEvent.AUTH_STATE_CHANGE:
        return 'authStateChange';
      default:
        return null;
    }
  }
}

abstract class SocketClusterClient {
  /// The hostname of the WebSocket URL to connect to.
  String get hostname;

  /// Whether or not the connection is over HTTP or HTTPS.
  bool get secure;

  /// The port of the WebSocket URL to connect to.
  /// Defaults to 443 if secure or 80 if not.
  int get port;

  /// The path which SocketCluster uses to make the initial handshake for the
  /// WebSocket.
  /// Defaults to '/socketcluster/'
  String get path;

  /// A map of key-value pairs which will be used as the query parameters for
  /// the initial HTTP handshake which will initiate the WebSocket connection.
  Map<String, String> get query;

  /// Returns the computed URL that the WebSocket client will connect to.
  String get url;

  /// The number of milliseconds to wait whilst attempting a connection to the
  /// server.
  /// Defaults to 20000 (20s).
  int connectTimeout;

  /// The number of milliseconds to wait for the response to an invoke action.
  /// Defaults to 10000 (10s).
  int ackTimeout;

  /// The auto-reconnect policy to adhere to if the connection to the socket
  /// server fails. Refer to [ReconnectPolicy] for defaults, etc.
  ReconnectPolicy reconnectPolicy;

  /// The list of sub-protocols to pass to the WebSocket server on connect.
  List<String> protocols;

  /// The list of headers to pass to the WebSocket server on connect.
  Map<String, dynamic> headers;

  /// The id of the socket connection. This is `null` initially and will change
  /// each time a new underlying connection is made.
  String get id;

  /// The id of the socket client. This does not change between connections.
  String get clientId;

  /// Changes the authentication token currently associated with the socket.
  /// Set this to `null` to indicate that no token should be associated with
  /// the socket.
  set authToken(String authToken);

  /// The current connection state of this socket.
  ConnectionState get state;

  /// The last known authentication state of the socket.
  AuthenticationState get authState;

  /// The interval in milliseconds between pings, as defined by the server upon
  /// handshaking. This will initially be null, until the handshake is complete
  /// and the value has been received from the server.
  int get pingInterval;

  /// Gets the close code from the underlying WebSocket which is set when the
  /// WebSocket is closed. If there is no close code available, this property
  /// will be [null].
  int get closeCode;

  /// Gets the close reason from the underlying WebSocket which is set when the
  /// WebSocket is closed. If there is no close reason available, this property
  /// will be [null].
  String get closeReason;

  factory SocketClusterClient({
    @required String hostname,
    bool secure = false,
    int port,
    String path = '/socketcluster/',
    Map<String, String> query,
    int connectTimeout = 20000,
    int ackTimeout = 10000,
    ReconnectPolicy reconnectPolicy = const ReconnectPolicy(),
    String authToken,
    String clientId,
  }) =>
      _SocketClusterClientImpl(
        hostname: hostname,
        secure: secure,
        port: port,
        path: path,
        query: query,
        connectTimeout: connectTimeout,
        ackTimeout: ackTimeout,
        reconnectPolicy: reconnectPolicy,
        authToken: authToken,
        clientId: clientId,
      );

  /// Connects the client socket to its origin server.
  Future connect();

  /// Send some raw data to the server. This will trigger a 'raw' event on the
  /// server-side which will carry the provided data.
  void send(String data);

  /// Transmits the specified event to the corresponding receiver on the
  /// server-side socket. Any JSON-compatible auxiliary data may be passed as
  /// [data].
  ///
  /// This method does not return anything, will not throw or reject and cannot
  /// be awaited.
  void transmit(
    String event, [
    dynamic data,
    Options options = const Options(),
  ]);

  /// Invoke the specified [procedure] (RPC) on the corresponding server-side
  /// socket. Any JSON-compatible auxiliary data may passed as [data].
  /// The returned [Future] is the response from the server.
  ///
  /// **NOTE:** If the [options] property has [Options.expectResponse] set to
  /// false, it will be implicitly overridden to true by the use of the [invoke]
  /// method. If you are not expecting a response, you should use [transmit]
  /// instead.
  ///
  /// There is a default timeout of 10 seconds to receive a response from the
  /// server as defined on the client ([ackTimeout]). This limit can be changed
  /// by either changing the [ackTimeout] property in the client constructor OR
  /// by setting the [Options.ackTimeout] on the [options] property for the
  /// invoke call.
  Future<dynamic> invoke(
    String procedure, [
    dynamic data,
    Options options = const Options(expectResponse: true),
  ]);

  /// Registers [callback] as an event handler for [event].
  ///
  /// To cancel the callback, you can call `.cancel` on the returned
  /// [StreamSubscription].
  StreamSubscription on(SCEvent event, Function callback);

  /// Registers [callback] as an event handler for the raw event - which is
  /// triggered whenever the server socket calls `socket.send(...)`. The object
  /// produced will have a 'message' property.
  ///
  /// THIS WILL NOT BE CALLED IF THE DATA CANNOT BE JSON-DECODED. You will need
  /// to use [onMessage] for that.
  ///
  /// To cancel the callback, you can call `.cancel` on the returned
  /// [StreamSubscription].
  StreamSubscription onRaw(Function(String data) callback);

  /// Registers [callback] as an event handler for the message event - which is
  /// triggered whenever a message is emitted through the socket.
  ///
  /// To cancel the callback, you can call `.cancel` on the returned
  /// [StreamSubscription].
  StreamSubscription onMessage(Function(String message) callback);

  /// Registers [callback] as a handler for the server-side transmitted event
  /// of [name]. This is essentially the reverse of the [transmit] function,
  /// i.e. when the server calls `.transmit(...)` on the client, this function's
  /// callback is called.
  StreamSubscription registerReceiver(
    String name,
    Function(dynamic data) callback,
  );

  /// Registers [callback] as a handler for the server-side transmitted remote
  /// procedure call (RPC) of [name]. This is essentially the reverse of the
  /// [invoke] function, i.e. when the server calls `.invoke(...)` on the
  /// client, this function's callback is called.
  StreamSubscription registerProcedure(
    String name,
    Function(dynamic data) callback,
  );

  /// Cleans up local data about the socket and explicitly closes the connection
  /// to the server ensuring that the client does not attempt to automatically
  /// reconnect.
  ///
  /// [code] is `1000` by default indicating normal closure and [reason] is null
  /// by default.
  Future<void> close([int code, String reason]);
}

class Options {
  final bool force;
  final bool cloneData;
  final bool expectResponse;
  final int ackTimeout;
  final bool noTimeout;

  const Options({
    this.force = false,
    this.cloneData = false,
    this.expectResponse = false,
    this.ackTimeout,
    this.noTimeout = false,
  });

  Options copyWith({
    bool force,
    bool cloneData,
    bool expectResponse,
    int ackTimeout,
    bool noTimeout,
  }) =>
      Options(
        force: force ?? this.force,
        cloneData: cloneData ?? this.cloneData,
        expectResponse: expectResponse ?? this.expectResponse,
        ackTimeout: ackTimeout ?? this.ackTimeout,
        noTimeout: noTimeout ?? this.noTimeout,
      );
}

class ConnectTimeoutError extends Error {
  final String message;
  ConnectTimeoutError(this.message);

  @override
  String toString() => 'Connect Timeout Error: $message';
}

class NetworkError extends Error {
  final String message;
  NetworkError(this.message);

  @override
  String toString() => 'Network Error: $message';
}

class SocketMessageError extends Error {
  final String name;
  final String message;
  final dynamic data;
  SocketMessageError(this.data, {this.name, this.message});

  @override
  String toString() =>
      'Request Error:${name != null ? ' $name' : ''} ${message ?? data}';
}
