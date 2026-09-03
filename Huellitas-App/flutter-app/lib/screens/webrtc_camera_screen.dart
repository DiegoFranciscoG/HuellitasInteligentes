import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/webrtc_config.dart';

/// Convierte el teléfono en una cámara IoT: abre la cámara trasera y
/// transmite el video en vivo por WebRTC a cualquier cantidad de visores
/// conectados, negociando la señalización por WebSocket/STOMP.
class WebRtcCameraScreen extends StatefulWidget {
  /// Identificador del stream que este dispositivo transmite; si no se da,
  /// se usa uno derivado del id del usuario autenticado.
  final String? urlStream;
  const WebRtcCameraScreen({super.key, this.urlStream});

  @override
  State<WebRtcCameraScreen> createState() => _WebRtcCameraScreenState();
}

class _WebRtcCameraScreenState extends State<WebRtcCameraScreen> {
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  StompClient? _stompClient;
  bool _isCameraActive = false;
  String _statusMessage = 'Inicializando cámara...';

  // Candidatos ICE pendientes y estado de SDP remoto, por visor (`from`)
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Map<String, bool> _isRemoteSet = {};


  @override
  void initState() {
    super.initState();
    initRenderers();
  }

  /// Inicializa el renderer local, abre la cámara del dispositivo y arranca
  /// la conexión STOMP para empezar a atender visores.
  Future<void> initRenderers() async {
    await _localRenderer.initialize();
    await _openCamera();
    _connectStomp();
  }

  /// Resolución que se le pide a la cámara. Va como `ideal` y no como `exact`
  /// a propósito: si el teléfono no puede dar 720p, negocia lo más cercano en
  /// vez de fallar al abrir la cámara.
  static const int _anchoDeseado = 1280;
  static const int _altoDeseado = 720;

  /// 24 cuadros por segundo alcanzan para vigilar una mascota, y dejan más
  /// ancho de banda disponible para el detalle de la imagen.
  static const int _cuadrosPorSegundo = 24;

  /// Techo de bitrate del emisor, en bits por segundo. Sin este piso, WebRTC
  /// estima solo y baja la calidad ante cualquier duda.
  static const int _bitrateMaximo = 2000000; // 2 Mbps

  Future<void> _openCamera() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': false, // Muteado por defecto
      'video': {
        'facingMode': 'environment', // Cámara trasera
        'width': {'ideal': _anchoDeseado},
        'height': {'ideal': _altoDeseado},
        'frameRate': {'ideal': _cuadrosPorSegundo},
      }
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      setState(() {
        _isCameraActive = true;
        _statusMessage = 'Cámara Activa. Esperando visores...';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error al abrir cámara: $e';
      });
    }
  }

  void _connectStomp() {
    final token = AuthService.token;
    final userId = AuthService.userData?['id'];
    if (token == null || userId == null) return;

    final streamId = widget.urlStream ?? 'webrtc:$userId';

    // Convertir http://ip:8087/api a ws://ip:8087/ws/websocket
    String wsUrl = ApiService.baseUrl.replaceFirst('http', 'ws').replaceAll('/api', '') + '/ws/websocket';

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: (StompFrame frame) {
          setState(() {
            _statusMessage = 'Conectado al servidor de Señalización';
          });
          _stompClient?.subscribe(
            destination: '/topic/webrtc/$streamId',
            callback: (StompFrame frame) {
              if (frame.body != null) {
                _handleIncomingSignal(jsonDecode(frame.body!));
              }
            },
          );
        },
        onWebSocketError: (dynamic error) => print(error.toString()),
        onStompError: (StompFrame frame) => print('STOMP Error: ${frame.body}'),
        onDisconnect: (StompFrame frame) => print('Desconectado'),
      ),
    );
    _stompClient?.activate();
  }

  void _handleIncomingSignal(Map<String, dynamic> message) async {
    String type = message['payload']['type'];
    String from = message['from'];

    if (type == 'command') {
      if (message['payload']['command'] == 'flip_camera') {
        if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
          Helper.switchCamera(_localStream!.getVideoTracks()[0]);
        }
      }
      return;
    }

    if (type == 'offer') {
      await _createPeerConnection(from);
      final pc = _peerConnections[from]!;

      RTCSessionDescription offer = RTCSessionDescription(
        message['payload']['sdp'],
        message['payload']['type'],
      );

      await pc.setRemoteDescription(offer);
      _isRemoteSet[from] = true;

      final pending = _pendingCandidates[from] ?? [];
      for (var c in pending) {
        await pc.addCandidate(c);
      }
      pending.clear();

      RTCSessionDescription answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      _sendSignal(from, {
        'type': 'answer',
        'sdp': answer.sdp
      });
    } else if (type == 'candidate') {
      RTCIceCandidate candidate = RTCIceCandidate(
        message['payload']['candidate']['candidate'],
        message['payload']['candidate']['sdpMid'],
        message['payload']['candidate']['sdpMLineIndex'],
      );
      if (_isRemoteSet[from] == true) {
        _peerConnections[from]?.addCandidate(candidate);
      } else {
        _pendingCandidates.putIfAbsent(from, () => []).add(candidate);
      }
    }
  }

  /// Fija el techo de bitrate y la preferencia de degradación del emisor de
  /// video. Lo segundo es lo que más se nota: ante poca banda, WebRTC
  /// sacrifica cuadros por segundo en vez de nitidez, que es lo que conviene
  /// para vigilar una mascota.
  Future<void> _ajustarCalidad(RTCRtpSender sender) async {
    try {
      final params = sender.parameters;

      final encodings = params.encodings;
      if (encodings == null || encodings.isEmpty) {
        params.encodings = [RTCRtpEncoding(maxBitrate: _bitrateMaximo)];
      } else {
        for (final encoding in encodings) {
          encoding.maxBitrate = _bitrateMaximo;
        }
      }
      params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;

      await sender.setParameters(params);
    } catch (e) {
      // Si la plataforma no admite ajustar parámetros, la transmisión sigue
      // funcionando con los valores por defecto; solo se pierde el piso de calidad.
      debugPrint('No se pudo ajustar la calidad del emisor: $e');
    }
  }

  Future<void> _createPeerConnection(String target) async {
    final existing = _peerConnections.remove(target);
    if (existing != null) {
      await existing.close();
    }
    _isRemoteSet[target] = false;
    _pendingCandidates[target] = [];

    final iceServers = await WebRtcConfig.iceServers;
    final pc = await createPeerConnection(iceServers);
    _peerConnections[target] = pc;

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        final sender = await pc.addTrack(track, _localStream!);
        if (track.kind == 'video') {
          await _ajustarCalidad(sender);
        }
      }
    }

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _sendSignal(target, {
        'type': 'candidate',
        'candidate': {
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'sdpMid': candidate.sdpMid,
          'candidate': candidate.candidate,
        }
      });
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      print('ICE Connection State ($target): $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        setState(() {
          _statusMessage = '¡Transmitiendo a ${_peerConnections.length} visor(es) remoto(s)!';
        });
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _peerConnections.remove(target);
        _isRemoteSet.remove(target);
        _pendingCandidates.remove(target);
        if (mounted) {
          setState(() {
            _statusMessage = _peerConnections.isEmpty
                ? 'Cámara Activa. Esperando visores...'
                : 'Transmitiendo a ${_peerConnections.length} visor(es) remoto(s)!';
          });
        }
      }
    };
  }

  void _sendSignal(String target, Map<String, dynamic> payload) {
    if (_stompClient?.connected == true) {
      final msg = {
        'target': target,
        'from': widget.urlStream ?? 'webrtc:${AuthService.userData?['id']}',
        'payload': payload
      };
      _stompClient?.send(
        destination: '/app/webrtc/signal',
        body: jsonEncode(msg),
      );
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _localStream?.dispose();
    for (final pc in _peerConnections.values) {
      pc.dispose();
    }
    _stompClient?.deactivate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Modo Cámara WebRTC', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          if (_isCameraActive)
            Center(
              child: RTCVideoView(_localRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _statusMessage,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.white, size: 16),
                  SizedBox(width: 5),
                  Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
