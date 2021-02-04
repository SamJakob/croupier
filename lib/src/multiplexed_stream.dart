part of croupier;

/// A stream multiplexer.
///
/// Allows for combining many related streams into one stream based on a
/// channel name, in effect 'multiplexing' many pseudo-streams (channels)
/// into one stream.
///
/// Note that for channels to be used with the [sourceStream], all events must
/// be transformed to [_ChanneledEvent] with the channel specified and all
/// errors must be transformed to [_ChanneledError].
class _MultiplexedStream<T> {
  static const GLOBAL_CHANNEL = '_global';

  final Stream<T> sourceStream;
  final StreamController _streamController;

  final Map<String, int> _streamListenerCount;

  final bool allowGlobalChannel;

  int getListenerCountForChannel(String channel) =>
      _streamListenerCount.containsKey(channel)
          ? _streamListenerCount[channel]
          : 0;

  int getTotalListenerCount() => _streamListenerCount.values.isEmpty
      ? 0
      : _streamListenerCount.values.reduce((sum, element) => sum + element);

  /// Creates a multiplexed stream with no existing [StreamSink] sources,
  /// allowing for data to be added to the stream directly using [add],
  /// [addToChannel], [addError] and [addErrorToChannel].
  _MultiplexedStream({this.allowGlobalChannel = true})
      : sourceStream = null,
        _streamController = StreamController.broadcast(),
        _streamListenerCount = {};

  /*_MultiplexedStream.fromSource({
    @required this.sourceStream,
  })  : _streamController = StreamController.broadcast(),
        _streamListenerCount = {} {
    _streamController.addStream(sourceStream, cancelOnError: false);
  }*/

  /// Adds a data [event] to the global channel meaning all subscribers,
  /// regardless of their channel will receive this event.
  void add(T event) {
    addToChannel(null, event);
  }

  /// Adds a data [event] to the specified [channel] meaning only subscribers
  /// for the specified channel will receive this event.
  void addToChannel(String channel, T event) {
    if (channel == null && !allowGlobalChannel) return;

    if (channel != null) {
      _streamController.add(_ChanneledEvent(channel, event));
    } else {
      _streamController.add(event);
    }
  }

  /// Adds an [error] to the global channel meaning all subscribers, regardless
  /// of their channel will receive this error.
  void addError(Object error, [StackTrace stackTrace]) {
    addErrorToChannel(null, error, stackTrace);
  }

  /// Adds an [error] to the specified [channel] meaning only subscribers for
  /// the specified channel will receive this error.
  void addErrorToChannel(String channel, Object error,
      [StackTrace stackTrace]) {
    if (channel == null && !allowGlobalChannel) return;

    if (channel != null) {
      _streamController.addError(_ChanneledError(channel, error, stackTrace));
    } else {
      _streamController.addError(error, stackTrace);
    }
  }

  /// Subscribes to the global event stream meaning only global events will be
  /// forwarded to this subscription.
  StreamSubscription subscribe(void Function(dynamic event) onData,
      {Function onError, void Function() onDone, bool cancelOnError}) {
    return subscribeToChannel(
      null,
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  /// Subscribes to the event stream for the specified [channel], meaning global
  /// events **and** the events for the specified channel will be forwarded
  /// to this subscription.
  StreamSubscription subscribeToChannel(
      String channel, void Function(dynamic event) onData,
      {Function onError, void Function() onDone, bool cancelOnError}) {
    _registerStreamSubscription(channel);

    return _streamController.stream.listen(
      (event) async {
        if (event is _ChanneledEvent) {
          if (event.channel == channel ||
              (event.channel == null && allowGlobalChannel)) {
            await onData(event);
          }

          return;
        }

        await onData(event);
      },
      onError: (error, [StackTrace stackTrace]) async {
        if (error is _ChanneledError) {
          if (error.channel == channel ||
              (error.channel == null && allowGlobalChannel)) {
            if (onError != null) await onError(error, error.stackTrace);
          }

          return;
        }

        if (onError != null) await onError(error, stackTrace);
      },
      onDone: () async {
        if (onDone != null) await onDone();
        _unregisterStreamSubscription(channel);
      },
      cancelOnError: cancelOnError,
    );
  }

  void _registerStreamSubscription(String channel) {
    if (channel == null && !allowGlobalChannel) return;
    channel ??= GLOBAL_CHANNEL;

    _streamListenerCount.putIfAbsent(channel, () => 0);
    _streamListenerCount[channel]++;
  }

  void _unregisterStreamSubscription(String channel) {
    if (channel == null && !allowGlobalChannel) return;
    channel ??= GLOBAL_CHANNEL;

    _streamListenerCount.putIfAbsent(channel, () => 0);

    if (_streamListenerCount[channel] < 1) {
      print(
          '[croupier] [multiplexed_stream] WARNING: Unregistered stream listener for $channel whilst streamListenerCount < 1; this indicates an error within the library.'
          'It has been handled gracefully but you should report this error to the developer as it could be indicative of an oversight or memory leak.');
    }

    _streamListenerCount[channel] = max(0, _streamListenerCount[channel] - 1);
  }

  Future<void> close() async {
    await _streamController.close();
  }
}

class _ChanneledEvent<T> {
  String channel;
  T event;

  _ChanneledEvent(this.channel, this.event);
}

class _ChanneledError<T> {
  String channel;
  Object error;
  StackTrace stackTrace;

  _ChanneledError(this.channel, this.error, [this.stackTrace]);
}
