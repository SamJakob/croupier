part of croupier;

class _SocketClusterClientImpl implements SocketClusterClient {
  static const SC_PROTOCOL_VERSION = 2;

  //**************************************************************************//
  //**************************************************************************//

  // Data passed from base type.

  @override
  String get hostname => _hostname;
  final String _hostname;

  @override
  bool get secure => _secure;
  final bool _secure;

  @override
  int get port => _port;
  final int _port;

  @override
  String get path => _path;
  final String _path;

  @override
  Map<String, String> get query => _query;
  final Map<String, String> _query;

  @override
  String get url => _url;
  final String _url;

  @override
  int connectTimeout;

  @override
  int ackTimeout;

  @override
  ReconnectPolicy reconnectPolicy;

  @override
  List<String> protocols;

  @override
  Map<String, dynamic> headers;

  @override
  String get id => _id;
  String _id;

  @override
  String get clientId => _clientId;
  final String _clientId;

  @override
  ConnectionState get state => _state;
  ConnectionState _state = ConnectionState.CLOSED;

  @override
  AuthenticationState get authState => _authState;
  AuthenticationState _authState = AuthenticationState.UNAUTHENTICATED;

  @override
  int get pingInterval => _pingInterval;
  int _pingInterval;

  String _authToken;
  @override
  set authToken(String authToken) {
    _authToken = authToken;
  }

  @override
  int get closeCode => _socket?.closeCode;

  @override
  String get closeReason => _socket?.closeReason;

  //**************************************************************************//
  //**************************************************************************//

  // Private implementation details.

  /// The current call ID, usually implemented as a counter.
  int _cid;

  /// The number of attempts that have been made to reconnect to the server
  /// since the connection was last lost.
  int _reconnectAttemptsMade;

  /// The interval to wait before next attempting to reconnect based on
  /// the current [reconnectPolicy] and the number of [_reconnectAttemptsMade].
  int getReconnectIntervalFor(int attemptsMade) {
    return ((reconnectPolicy.initialDelay +
                    (reconnectPolicy.randomness * Random().nextDouble()))
                .round() *
            pow(reconnectPolicy.multiplier, attemptsMade))
        .round();
  }

  final Map<int, Completer<dynamic>> _expectedResponses;
  final ListQueue<Map<String, dynamic>> _outboundBuffer;

  //**************************************************************************//
  //**************************************************************************//

  // Interface with WebSocket.

  /// The underlying WebSocket connection.
  WebSocket _socket;

  _MultiplexedStream _eventsMultiplex;
  _MultiplexedStream _receiveMultiplex;
  _MultiplexedStream _invokeMultiplex;
  //_MultiplexedStream _channelDemux;

  //**************************************************************************//
  //**************************************************************************//

  _SocketClusterClientImpl({
    @required String hostname,
    bool secure = false,
    int port,
    String path = '/socketcluster/',
    Map<String, String> query,
    this.connectTimeout = 20000,
    this.ackTimeout = 10000,
    this.reconnectPolicy = const ReconnectPolicy(),
    this.protocols,
    this.headers,
    String authToken,
    String clientId,
  })  : _hostname = hostname,
        _secure = secure,
        _port = port,
        _path = path,
        _query = query,
        _url = Uri(
          scheme: secure ? 'wss' : 'ws',
          host: hostname,
          port: port ?? (secure ? 443 : 80),
          path: path,
          queryParameters: query,
        ).toString(),
        _authToken = authToken,
        _clientId = clientId,
        _expectedResponses = {},
        _outboundBuffer = Queue<Map<String, dynamic>>(),
        _eventsMultiplex = _MultiplexedStream(),
        _receiveMultiplex = _MultiplexedStream(),
        _invokeMultiplex = _MultiplexedStream();

  @override
  Future connect() async {
    if (_state != ConnectionState.CLOSED) {
      return Future.error(StateError(
        "Socket already open. This error occurs when you call .connect() on a socket that's already open.",
      ));
    }

    _eventsMultiplex ??= _MultiplexedStream();
    _invokeMultiplex ??= _MultiplexedStream();
    _receiveMultiplex ??= _MultiplexedStream();
    //_channelEventDemux = _MultiplexedStream();
    //_channelDataDemux = _MultiplexedStream();
    //_receiverDemux = _MultiplexedStream();

    bool _connected = false;
    while (!_connected) {
      _cid = -1;
      _reconnectAttemptsMade = 0;
      _state = ConnectionState.CONNECTING;
      _emit(SCEvent.CONNECTING);

      try {
        _socket = await WebSocket.connect(
          url,
          protocols: protocols,
          headers: headers,
        ).timeout(Duration(milliseconds: connectTimeout), onTimeout: () {
          _onSocketClose();
          throw ConnectTimeoutError(
              'Connect timed out after ${connectTimeout}ms');
        });
      } catch (_) {
        await _reconnectDelay();
        continue;
      }

      _socket.listen(
        _onSocketMessage,
        onError: _onSocketError,
        onDone: _onSocketClose,
        cancelOnError: false,
      );
      await _onSocketOpen();
      _connected = true;
    }
  }

  void _onSocketOpen() async {
    var status = await invoke(
      '#handshake',
      {'authToken': _authToken},
      Options(force: true),
    );

    _id = status['id'];
    _pingInterval = status['pingTimeout'];
    if (status['isAuthenticated']) {
      _authState = AuthenticationState.AUTHENTICATED;
      _emit(SCEvent.AUTH_STATE_CHANGE);
    } else {
      _authState = AuthenticationState.UNAUTHENTICATED;
      _authToken = null;
      _emit(SCEvent.AUTH_STATE_CHANGE);
    }
    _reconnectAttemptsMade = 0;

    _state = ConnectionState.OPEN;
    _flushOutboundBuffer();
  }

  void _onSocketMessage(dynamic message) {
    // Handle message
    _emitEvent('message', message.toString());

    // Handle ping
    if (message == '') {
      send('');
      return;
    }

    // Handle list
    if (message is List) {
      message.forEach((element) {
        _onSocketMessage(element);
      });

      return;
    }

    try {
      // Handle packet
      var packet = jsonDecode(message);

      if (packet['event'] != null) {
        if (packet['cid'] != null) {
          _emitInvoke(packet['event'], packet);
        } else {
          _emitReceive(packet['event'], packet);
        }

        return;
      }

      if (packet['rid'] != null) {
        if (_expectedResponses.containsKey(packet['rid'])) {
          if (packet['error'] != null) {
            _expectedResponses[packet['rid']].completeError(
              SocketMessageError(
                packet['error'],
                name: packet['error']['name'],
                message: packet['error']['message'],
              ),
            );
          } else {
            _expectedResponses[packet['rid']].complete(packet['data']);
          }
        }

        return;
      }

      _emitEvent('raw', message);
    } catch (ex, stacktrace) {
      print('Error handling message: $message');
      print(ex);
      print(stacktrace);
    }
  }

  void _onSocketError(Object error, [StackTrace stackTrace]) {}

  void _onSocketClose() {
    var code = _socket.closeCode;
    _emit(SCEvent.DISCONNECT);

    if (reconnectPolicy.autoReconnect) {
      // 1005 - close without status
      // 4000 - server ping timeout
      // 4001 - client pong timeout
      if (code != 1000 && code < 4500) {
        // If there's a ping/pong timeout or the server closed without status
        // simply attempt to reconnect immediately as these may simply occur if
        // the client wakes up after a period of inactivity - in which case
        // we want to restore the connection ASAP.
        if (code == 1005 || code == 4000 || code == 4001) {
          return _reconnectDelay(0);
        }

        return _reconnectDelay();
      }
    }
  }

  void _reconnectDelay([int initialDelay]) async {
    // 1. Compute the timeout.
    var timeout = initialDelay;
    if (timeout == null) {
      if (_reconnectAttemptsMade > 0) {
        getReconnectIntervalFor(_reconnectAttemptsMade);
      } else {
        timeout = 0;
      }
    }

    timeout = min(timeout, reconnectPolicy.maxDelay);

    // 2. Attempt to reconnect after awaiting the timeout
    await Future.delayed(Duration(milliseconds: timeout));
    // connect

    // 3. Increment the number of attempts made to reconnect to the server.
    _reconnectAttemptsMade++;
  }

  void _cleanUp() {
    _authState = AuthenticationState.UNAUTHENTICATED;
    _emit(SCEvent.AUTH_STATE_CHANGE);

    _outboundBuffer.clear();
    _state = ConnectionState.CLOSED;

    //_channelEventDemux.close();
    //_channelDataDemux.close();
    //_receiverDemux.close();

    _eventsMultiplex.close();
    _eventsMultiplex = null;

    _receiveMultiplex.close();
    _receiveMultiplex = null;

    _invokeMultiplex.close();
    _invokeMultiplex = null;
  }

  //**************************************************************************//
  //**************************************************************************//

  // Protocol API

  @override
  void send(String data) {
    if (state != ConnectionState.OPEN) {
      close(1005);
    } else {
      _socket.add(data);
    }
  }

  @override
  void transmit(
    String event, [
    dynamic data,
    Options options = const Options(),
  ]) {
    _processOutboundEvent(event, data, options);
  }

  @override
  Future<dynamic> invoke(
    String procedure, [
    dynamic data,
    Options options = const Options(expectResponse: true),
  ]) async {
    return await _processOutboundEvent(
      procedure,
      data,
      options.copyWith(expectResponse: true),
    );
  }

  @override
  StreamSubscription on(SCEvent event, Function callback) {
    return _eventsMultiplex.subscribeToChannel(event.name, (event) {
      try {
        if (callback != null) callback();
      } catch (ex, stacktrace) {
        print('An error occurred whilst processing a $event event.');
        print(ex);
        print(stacktrace);
      }
    });
  }

  @override
  StreamSubscription onRaw(Function(String data) callback) {
    return _eventsMultiplex.subscribeToChannel('raw', (event) {
      try {
        if (callback != null) callback(event.event.toString());
      } catch (ex, stacktrace) {
        print('An error occurred whilst processing a raw event.');
        print(ex);
        print(stacktrace);
      }
    });
  }

  @override
  StreamSubscription onMessage(Function(String data) callback) {
    return _eventsMultiplex.subscribeToChannel('message', (event) {
      try {
        if (callback != null) callback(event.event.toString());
      } catch (ex, stacktrace) {
        print('An error occurred whilst processing a raw event.');
        print(ex);
        print(stacktrace);
      }
    });
  }

  @override
  StreamSubscription registerReceiver(
    String name,
    Function(dynamic data) callback,
  ) {
    return _receiveMultiplex.subscribeToChannel(name, (
      dynamic event,
    ) {
      try {
        if (callback != null) callback(event.event);
      } catch (ex, stacktrace) {
        print('An error occurred whilst processing a raw event.');
        print(ex);
        print(stacktrace);
      }
    });
  }

  @override
  StreamSubscription registerProcedure(
    String name,
    Function(dynamic data) callback,
  ) {
    return _invokeMultiplex.subscribeToChannel(name, (event) async {
      int rid = event.event['cid'];

      try {
        if (callback != null) {
          var response = await callback(event.event);

          await _processOutboundEvent(
            null,
            response,
            const Options(),
            rid,
          );
        }
      } catch (ex, stacktrace) {
        print('An error occurred whilst processing a raw event.');
        print(ex);
        print(stacktrace);
      }
    });
  }

  @override
  Future<void> close([int code, String reason]) async {
    if (_state != ConnectionState.CLOSED) {
      _emit(SCEvent.CLOSE);
      _clearExpectedResponses();

      // Close the socket.
      if (_socket != null) await _socket.close(code ?? 1000, reason);

      // Allow socket time to close and trigger events before cleaning up.
      await Future.delayed(Duration(milliseconds: 10));

      // Clean up.
      _cleanUp();
    }
  }

  //**************************************************************************//
  //**************************************************************************//

  // Protocol Implementation

  Future<dynamic> _processOutboundEvent(
    String event,
    dynamic data, [
    Options options = const Options(),
    int rid,
  ]) async {
    if (state == ConnectionState.CLOSED) {
      await connect();
    }

    data ??= {};

    var cid;
    if (options.expectResponse) cid = ++_cid;

    var outboundPacket = <String, dynamic>{
      'cid': cid,
      'rid': rid,
      'event': event,
      'data': (data is Map && options.cloneData) ? {...data} : data,
    };

    var responseFuture;

    // Add an 'expected response' for this call ID to the expected responses
    // array if the response is, in fact, expected.
    if (options.expectResponse) {
      var outboundEventCompleter = Completer();
      _expectedResponses[cid] = outboundEventCompleter;
      responseFuture = outboundEventCompleter.future;
      if (!options.noTimeout) {
        responseFuture = responseFuture.timeout(Duration(
          milliseconds: options.ackTimeout ?? ackTimeout,
        ));
      }
    }

    // Add the data to the outbound queue.
    _outboundBuffer.add(outboundPacket);

    // ...and flush the queue if the connection is still good.
    if (state == ConnectionState.OPEN || options.force) {
      _flushOutboundBuffer();
    }

    // This will either return null (in the instance we don't care about
    // the response) or it'll return a future that can be awaited to obtain
    // the response assuming it comes back from the server before the timeout
    // is exceeded.
    return responseFuture;
  }

  void _flushOutboundBuffer() {
    _outboundBuffer.removeWhere((outboundPacket) {
      try {
        _socket.add(jsonEncode(outboundPacket));
        return true;
      } catch (er) {
        return false;
      }
    });
  }

  void _clearExpectedResponses() async {
    for (var expectedResponseKey in _expectedResponses.keys) {
      var expectedResponse = _expectedResponses[expectedResponseKey];
      if (!expectedResponse.isCompleted) {
        expectedResponse.completeError(
          NetworkError(
            'Event #${expectedResponseKey} was aborted.',
          ),
        );
      }
    }
  }

  void _emit(SCEvent event) {
    _eventsMultiplex.addToChannel(event.name, null);
  }

  void _emitEvent(String event, [dynamic data]) {
    _eventsMultiplex.addToChannel(event, data);
  }

  void _emitReceive(String event, dynamic data) {
    _receiveMultiplex.addToChannel(event, data);
  }

  void _emitInvoke(String event, dynamic data) {
    _invokeMultiplex.addToChannel(event, data);
  }
}
