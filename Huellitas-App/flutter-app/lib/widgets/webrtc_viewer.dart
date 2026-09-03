import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/webrtc_config.dart';

/// Visor de video en vivo de una cámara IoT vía WebRTC.
///
/// Negocia la conexión punto a punto con el emisor identificado por
/// [targetStream] usando señalización por WebSocket/STOMP (oferta/respuesta
/// SDP e intercambio de candidatos ICE) y muestra el video remoto una vez
/// establecida la conexión.
class WebRtcViewer extends StatefulWidget {
  /// Identificador del emisor (cámara) al que este visor debe conectarse.
  final String targetStream;

  const WebRtcViewer({super.key, required this.targetStream});

  @override
  State<WebRtcViewer> createState() => _WebRtcViewerState();
}

class _WebRtcViewerState extends State<WebRtcViewer> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  StompClient? _stompClient;
  String _statusMessage = 'Conectando a cámara...';

  // El broadcaster empieza a mandar candidatos ICE en cuanto crea su
  // PeerConnection, lo que suele llegar ANTES de que el 'answer' termine de
  // procesarse aquí. Sin este buffer, addCandidate() fallaba silenciosamente
  // y la conexión nunca completaba el video (se quedaba "conectando").
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _isRemoteSet = false;


  @override
  void initState() {
    super.initState();
    initRenderers();
  }

  /// Inicializa el renderer de video remoto y arranca la conexión STOMP
  /// para empezar la señalización WebRTC.
  Future<void> initRenderers() async {
    await _remoteRenderer.initialize();
    _connectStomp();
  }

  void _connectStomp() {
    final token = AuthService.token;
    final userId = AuthService.userData?['id'];
    if (token == null || userId == null) return;

    String wsUrl = ApiService.baseUrl.replaceFirst('http', 'ws').replaceAll('/api', '') + '/ws/websocket';

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: (StompFrame frame) {
          setState(() {
            _statusMessage = 'Negociando P2P...';
          });
          _stompClient?.subscribe(
            destination: '/topic/webrtc/viewer-$userId',
            callback: (StompFrame frame) {
              if (frame.body != null) {
                final message = jsonDecode(frame.body!);
                if (message['from'] == widget.targetStream) {
                  _handleIncomingSignal(message['payload']);
                }
              }
            },
          );

          // Iniciar la llamada
          _createOffer();
        },
        onWebSocketError: (dynamic error) => print('WS Error: $error'),
        onStompError: (StompFrame frame) => print('STOMP Error: ${frame.body}'),
        onDisconnect: (StompFrame frame) => print('Desconectado'),
      ),
    );
    _stompClient?.activate();
  }

  Future<void> _createOffer() async {
    final iceServers = await WebRtcConfig.iceServers;
    _peerConnection = await createPeerConnection(iceServers);

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _sendSignal({
        'type': 'candidate',
        'candidate': {
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'sdpMid': candidate.sdpMid,
          'candidate': candidate.candidate,
        }
      });
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams[0];
        setState(() {
          _statusMessage = 'Conectado';
        });
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      print('ICE Connection State (Viewer): $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        setState(() {
          _statusMessage = 'Conectado';
        });
      }
    };

    // Agregar transceiver solo para recibir video
    await _peerConnection!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _sendSignal({
      'type': 'offer',
      'sdp': offer.sdp,
    });
  }

  void _handleIncomingSignal(Map<String, dynamic> payload) async {
    String type = payload['type'];

    if (type == 'answer') {
      RTCSessionDescription answer = RTCSessionDescription(
        payload['sdp'],
        type,
      );
      await _peerConnection?.setRemoteDescription(answer);
      _isRemoteSet = true;
      for (final c in _pendingCandidates) {
        await _peerConnection?.addCandidate(c);
      }
      _pendingCandidates.clear();
    } else if (type == 'candidate') {
      RTCIceCandidate candidate = RTCIceCandidate(
        payload['candidate']['candidate'],
        payload['candidate']['sdpMid'],
        payload['candidate']['sdpMLineIndex'],
      );
      if (_isRemoteSet) {
        _peerConnection?.addCandidate(candidate);
      } else {
        _pendingCandidates.add(candidate);
      }
    }
  }

  void _sendSignal(Map<String, dynamic> payload) {
    if (_stompClient?.connected == true) {
      final userId = AuthService.userData?['id'];
      final msg = {
        'target': widget.targetStream,
        'from': 'viewer-$userId',
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
    _remoteRenderer.dispose();
    _peerConnection?.close();
    _peerConnection?.dispose();
    _stompClient?.deactivate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: Colors.black,
          child: RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
        if (_statusMessage != 'Conectado')
          Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.indigoAccent),
                  const SizedBox(height: 12),
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        if (_statusMessage == 'Conectado')
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.2),
                border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 10),
                  SizedBox(width: 4),
                  Text('LIVE', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
