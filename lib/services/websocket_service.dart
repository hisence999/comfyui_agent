import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();
  final StreamController<Uint8List> _previewController = StreamController.broadcast();
  
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Uint8List> get previewStream => _previewController.stream;
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  final String clientId = const Uuid().v4();
  Timer? _reconnectTimer;

  Future<void> connect(String address) async {
    _reconnectTimer?.cancel();
    disconnect();
    
    try {
      String wsAddress = address.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
      final wsUrl = Uri.parse('$wsAddress/ws?clientId=$clientId');
      print('Connecting to WS with ClientID $clientId: $wsUrl');
      
      _channel = WebSocketChannel.connect(wsUrl);
      _isConnected = true;
      
      _channel!.stream.listen(
        (message) {
          if (message is String) {
            try {
              final data = jsonDecode(message);
              _messageController.add(data);
            } catch (e) {
              print('Error decoding WS message: $e');
            }
          } else if (message is Uint8List) {
            _previewController.add(message);
          }
        },
        onDone: () {
          print('WS Connection Closed, scheduling reconnect...');
          _isConnected = false;
          _scheduleReconnect(address);
        },
        onError: (error) {
          print('WS Error: $error, scheduling reconnect...');
          _isConnected = false;
          _scheduleReconnect(address);
        },
      );
    } catch (e) {
      print('WS Connection Failed: $e');
      _isConnected = false;
      _scheduleReconnect(address);
    }
  }

  void _scheduleReconnect(String address) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_isConnected) connect(address);
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
      _isConnected = false;
    }
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _previewController.close();
  }
}
