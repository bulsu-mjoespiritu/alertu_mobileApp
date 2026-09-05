import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:number_flow_flutter/number_flow_flutter.dart';
import 'package:alertu_flutter/services/api_service.dart';
import 'package:alertu_flutter/services/socket.dart';
import 'package:alertu_flutter/services/callringtone_service.dart'; // Outgoing ringtone
import 'package:alertu_flutter/services/ringtone_service.dart';      // Missed call ringtone
import 'package:alertu_flutter/services/bubble_service.dart';
import 'package:alertu_flutter/subpages/emergency_chats.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AgoraCallScreen extends StatefulWidget {
  final String channelName;
  final String? backendUrl;
  final String? callerName;
  final String? citizenId;

  const AgoraCallScreen({
    super.key,
    required this.channelName,
    this.backendUrl,
    this.callerName,
    this.citizenId,
  });

  @override
  State<AgoraCallScreen> createState() => _AgoraCallScreenState();
}

class _AgoraCallScreenState extends State<AgoraCallScreen> {
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _isMuted = false;
  bool _isVideoDisabled = false;
  // The admin starts audio-only; this changes when the admin enables video.
  bool _isRemoteVideoMuted = true;

  late RtcEngine _engine;
  bool _isEngineInitialized = false;
  bool _hasLeftCall = false;

  // 🔔 Missed Call & Answer States
  bool _hasAdminConnected = false;
  static const int _startRingtoneSecond = 40;
  static const int _totalTimeoutSeconds = 49;

  bool _isRingtonePhaseActive = false;
  int _ringtoneElapsedSeconds = 0;
  Timer? _ringtoneStartTimer;
  Timer? _ringtoneTicker;
  Timer? _missedCallTimeoutTimer;

  // ⏱️ 5-Minute Call Duration Limit
  static const int _callDurationLimit = 120;
  int _secondsRemaining = _callDurationLimit;
  Timer? _countdownTimer;

  bool _hasMinimizedToChat = false;
  bool _hasBubbleBeenTriggered = false;
  DateTime? _callStartTime;

  @override
  void initState() {
    super.initState();
    _initAgora();
    _listenToCallSignals();
    _listenForAccountDeactivation(); // Active call deactivation listener
  }

  /// 🔒 Listens for account deactivation signals during active call
  void _listenForAccountDeactivation() {
    SocketService.listenForAccountDeactivation((data) async {
      if (!mounted || _hasLeftCall) return;

      final String? targetCitizenId = (data['citizenId'] ?? data['citizen_id'] ?? data['id'])?.toString();
      final String? targetSubmitterName = (data['submitterName'] ?? data['submitter_name'] ?? data['citizenName'] ?? data['citizen_name'])?.toString();

      final String currentCitizenId = (widget.citizenId ?? '').trim();
      final String currentCallerName = (widget.callerName ?? '').trim();

      bool isMatch = false;

      if (currentCitizenId.isNotEmpty && targetCitizenId != null) {
        if (targetCitizenId.trim().toLowerCase() == currentCitizenId.toLowerCase()) {
          isMatch = true;
        }
      }

      if (!isMatch && currentCallerName.isNotEmpty && targetSubmitterName != null) {
        if (targetSubmitterName.trim().toLowerCase() == currentCallerName.toLowerCase()) {
          isMatch = true;
        }
      }

      if (isMatch) {
        debugPrint('🛑 Account deactivated during active Agora Call! Force ending call...');
        await _leaveCall(endedByReason: 'account_deactivated');
      }
    });
  }

  void _startRingtoneTimeoutSequence() {
    CallRingtoneService.startRingtone();

    _ringtoneStartTimer?.cancel();
    _ringtoneStartTimer = Timer(const Duration(seconds: _startRingtoneSecond), () {
      if (!_hasAdminConnected && mounted && !_hasLeftCall) {
        debugPrint('⏰ 20s reached. Stopping callringtone.mp3 and switching to missedcallring.mp3...');

        CallRingtoneService.stopRingtone();
        RingtoneService.startRingtone();

        setState(() {
          _isRingtonePhaseActive = true;
          _ringtoneElapsedSeconds = 0;
        });

        _ringtoneTicker?.cancel();
        _ringtoneTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted || _hasAdminConnected || _hasLeftCall) {
            timer.cancel();
            return;
          }
          if (_ringtoneElapsedSeconds < 8) {
            setState(() {
              _ringtoneElapsedSeconds++;
            });
          } else {
            timer.cancel();
          }
        });
      }
    });

    _missedCallTimeoutTimer?.cancel();
    _missedCallTimeoutTimer = Timer(const Duration(seconds: _totalTimeoutSeconds), () {
      if (!_hasAdminConnected && mounted && !_hasLeftCall) {
        debugPrint('🚫 28s reached. Auto-ending call as Missed Call.');
        _cancelRingtoneTimers();
        _leaveCall(endedByReason: 'no_answer');
      }
    });
  }

  void _cancelRingtoneTimers() {
    _ringtoneStartTimer?.cancel();
    _ringtoneTicker?.cancel();
    _missedCallTimeoutTimer?.cancel();

    CallRingtoneService.stopRingtone();
    RingtoneService.stopRingtone();
  }

  void _startCallDurationTimer() {
    _cancelRingtoneTimers();

    _callStartTime = DateTime.now();
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      final int elapsedCallSeconds = _callDurationLimit - _secondsRemaining;

      if (elapsedCallSeconds >= 10) {
        if (!_hasBubbleBeenTriggered) {
          setState(() {
            _hasBubbleBeenTriggered = true;
          });
        }

        if (!_hasMinimizedToChat) {
          _hasMinimizedToChat = true;
          _minimizeToEmergencyChat();
        }
      }

      if (_secondsRemaining <= 1) {
        timer.cancel();
        debugPrint('⏱️ 5-minute limit reached. Auto-ending call.');
        _leaveCall(endedByReason: 'timer_timeout');
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  Future<void> _minimizeToEmergencyChat() async {
    debugPrint('🫧 Minimizing call and launching bubble/chat screen...');
    await BubbleService.startBubble();

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SimpleChat(
            channelName: widget.channelName,
            engine: _engine,
          ),
        ),
      );
    }
  }

  String _formattedTime(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _listenToCallSignals() {
    SocketService.listenForCallEvents(
      onCallEnded: (data) {
        debugPrint('⏹️ Admin ended/declined call signal received.');
        if (!_hasLeftCall) {
          _leaveCall(endedByReason: 'admin');
        }
      },
    );
  }

  Future<void> _saveCallHistory({String endedByReason = 'citizen'}) async {
    try {
      if (ApiService.baseUrl == null && widget.backendUrl == null) {
        await ApiService.initBackend();
      }

      String resolvedUrl = widget.backendUrl ?? ApiService.baseUrl!;
      if (!resolvedUrl.endsWith('/api')) {
        resolvedUrl = resolvedUrl.endsWith('/') ? '${resolvedUrl}api' : '$resolvedUrl/api';
      }

      int durationSeconds = 0;
      if (_callStartTime != null) {
        durationSeconds = DateTime.now().difference(_callStartTime!).inSeconds;
      }

      final String callStatus = (_hasAdminConnected && durationSeconds > 0) ? 'completed' : 'missed';

      final historyTargetUri = Uri.parse('$resolvedUrl/call-history');
      debugPrint('📝 Posting call history payload ($callStatus) to: $historyTargetUri');

      await http.post(
        historyTargetUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channelName': widget.channelName,
          'citizenName': widget.callerName ?? 'Emergency Citizen',
          'citizenId': widget.citizenId,
          'adminId': null,
          'adminName': 'Dispatcher',
          'duration': durationSeconds,
          'endedBy': endedByReason,
          'status': callStatus,
          'callType': 'emergency_video',
        }),
      ).timeout(const Duration(seconds: 5));

    } catch (e) {
      debugPrint('❌ Failed to post call history: $e');
    }
  }

  Future<void> _initAgora() async {
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.microphone,
        Permission.camera
      ].request();

      if (statuses[Permission.microphone]!.isDenied || statuses[Permission.camera]!.isDenied) {
        throw Exception('Camera or Microphone access authorization was rejected.');
      }

      if (ApiService.baseUrl == null && widget.backendUrl == null) {
        await ApiService.initBackend();
      }

      String resolvedUrl = widget.backendUrl ?? ApiService.baseUrl!;
      if (!resolvedUrl.endsWith('/api')) {
        resolvedUrl = resolvedUrl.endsWith('/') ? '${resolvedUrl}api' : '$resolvedUrl/api';
      }

      final tokenTargetUri = Uri.parse(
        '$resolvedUrl/agora-token'
            '?channelName=${Uri.encodeComponent(widget.channelName)}'
            '&citizenId=${Uri.encodeComponent(widget.citizenId ?? '')}'
            '&callerName=${Uri.encodeComponent(widget.callerName ?? '')}',
      );
      final response = await http.get(tokenTargetUri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw Exception('Token generator rejected request (${response.statusCode})');
      }

      final data = jsonDecode(response.body);
      final String token = data['token'];
      final String appId = data['appId'];

      _engine = createAgoraRtcEngine();
      await _engine.initialize(RtcEngineContext(appId: appId));

      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint('✅ Channel joined successfully.');
            if (mounted) {
              setState(() => _localUserJoined = true);
              _startRingtoneTimeoutSequence();
            }
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint('👤 Dispatcher answered call! UID: $remoteUid');

            _cancelRingtoneTimers();

            if (mounted) {
              setState(() {
                _remoteUid = remoteUid;
                _hasAdminConnected = true;
                _isRingtonePhaseActive = false;
              });
              _startCallDurationTimer();
            }
          },
          // React admin can publish video after joining. Update the mobile
          // renderer when that opt-in camera is enabled or disabled.
          onUserEnableVideo: (RtcConnection connection, int remoteUid, bool enabled) {
            if (mounted && remoteUid == _remoteUid) {
              setState(() => _isRemoteVideoMuted = !enabled);
            }
          },
          onUserMuteVideo: (RtcConnection connection, int remoteUid, bool muted) {
            if (mounted && remoteUid == _remoteUid) {
              setState(() => _isRemoteVideoMuted = muted);
            }
          },

          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            debugPrint('👤 Remote dispatcher offline. Teardown call.');
            if (mounted) {
              setState(() {
                _remoteUid = null;
                _isRemoteVideoMuted = true;
              });
            }
            _leaveCall(endedByReason: 'admin');
          },
          onError: (ErrorCodeType err, String msg) {
            debugPrint('❌ Engine Exception [$err]: $msg');
          },
        ),
      );

      await _engine.enableVideo();

      // 🎥 STRICT 360P ENCODER CONFIGURATION
      await _engine.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 360),
          frameRate: 15,
          bitrate: 400,
          orientationMode: OrientationMode.orientationModeAdaptive,
        ),
      );

      await _engine.startPreview();
      await _engine.setChannelProfile(ChannelProfileType.channelProfileCommunication);

      await _engine.joinChannel(
        token: token,
        channelId: widget.channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );

      if (mounted) {
        setState(() => _isEngineInitialized = true);
      }

      SocketService.sendCallInvite(
        targetRoom: 'admins',
        channelName: widget.channelName,
        isVideo: true,
        callerName: widget.callerName ?? 'Emergency Citizen',
        citizenId: widget.citizenId,
      );

    } catch (e) {
      debugPrint('❌ Connection breakdown: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call initialisation failed: $e'), backgroundColor: Colors.redAccent),
        );
        _leaveCall(endedByReason: 'error');
      }
    }
  }

  /// 🛑 Centralized Call Termination & Stack Dismissal
  Future<void> _leaveCall({String endedByReason = 'citizen'}) async {
    if (_hasLeftCall) return;
    _hasLeftCall = true;

    _cancelRingtoneTimers();
    _countdownTimer?.cancel();
    await BubbleService.stopBubble();

    await _saveCallHistory(endedByReason: endedByReason);

    try {
      SocketService.endCall(
        channelName: widget.channelName,
        targetRoom: 'admins',
      );
    } catch (socketErr) {
      debugPrint('⚠️ Signaling drop: $socketErr');
    }

    if (_isEngineInitialized) {
      try {
        await _engine.stopPreview();
        await _engine.leaveChannel();
        await _engine.release();
      } catch (e) {
        debugPrint('Error tearing down RTC engine: $e');
      } finally {
        _isEngineInitialized = false;
      }
    }

    SocketService.clearCallListeners();

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _toggleMute() {
    if (!_isEngineInitialized) return;
    setState(() => _isMuted = !_isMuted);
    _engine.muteLocalAudioStream(_isMuted);
  }

  void _toggleVideo() async {
    if (!_isEngineInitialized) return;
    final nextState = !_isVideoDisabled;
    setState(() => _isVideoDisabled = nextState);

    await _engine.muteLocalVideoStream(nextState);
    await _engine.enableLocalVideo(!nextState);
  }

  void _switchCamera() {
    if (!_isEngineInitialized) return;
    _engine.switchCamera();
  }

  @override
  void dispose() {
    _cancelRingtoneTimers();
    _countdownTimer?.cancel();
    BubbleService.stopBubble();

    if (!_hasLeftCall && _isEngineInitialized) {
      _hasLeftCall = true;
      _saveCallHistory(endedByReason: 'citizen');
      SocketService.endCall(
        channelName: widget.channelName,
        targetRoom: 'admins',
      );
      _engine.stopPreview();
      _engine.leaveChannel();
      _engine.release();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isWarning = _secondsRemaining <= 60;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Center Screen: Video view or Audio-only view / ringing states
          Center(
            child: _isEngineInitialized && _remoteUid != null
                ? (!_isRemoteVideoMuted
                ? AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: _engine,
                canvas: VideoCanvas(uid: _remoteUid),
                connection: RtcConnection(channelId: widget.channelName),
              ),
            )
                : Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: Colors.white10,
                      child: Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 42),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Emergency Dispatcher',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Dispatcher camera is off',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),

                  ],
                ),
              ),
            ))
                : AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: ScaleTransition(scale: animation, child: child));
              },
              child: (_isRingtonePhaseActive && !_hasAdminConnected)
                  ? Container(
                key: const ValueKey('telecomRingingState'),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.4), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone_in_talk_rounded, color: Colors.redAccent, size: 44),
                    const SizedBox(height: 12),
                    const Text(
                      'NO ANSWER / RINGING',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ringing Emergency Dispatcher...',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '0:0',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        NumberFlow(
                          value: _ringtoneElapsedSeconds,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
                  : const Column(
                key: ValueKey('callingState'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 3),
                  SizedBox(height: 20),
                  Text(
                    'Calling Dispatcher...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Countdown Timer Overlay
          if (_localUserJoined && _hasAdminConnected)
            Positioned(
              top: 50,
              left: 20,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isWarning ? Colors.red.withOpacity(0.85) : Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isWarning ? Colors.white : Colors.white24,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      color: isWarning ? Colors.white : Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formattedTime(_secondsRemaining),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 3. 🫧 Manual Minimize Button
          if (_hasBubbleBeenTriggered)
            Positioned(
              top: 50,
              left: 115,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _minimizeToEmergencyChat,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: const Icon(
                      LucideIcons.messageCircle,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),

          // 4. Local Camera Preview
          Positioned(
            top: 50,
            right: 20,
            width: 110,
            height: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: Colors.black,
                child: _isEngineInitialized && _localUserJoined && !_isVideoDisabled
                    ? AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: _engine,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                )
                    : const Center(
                  child: Icon(Icons.videocam_off, color: Colors.white38, size: 28),
                ),
              ),
            ),
          ),

          // 5. Operational Controls Bar
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(
                    _isMuted ? Icons.mic_off : Icons.mic,
                    color: _isMuted ? Colors.redAccent : Colors.white,
                    size: 28,
                  ),
                  onPressed: _toggleMute,
                ),
                IconButton(
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 28),
                  onPressed: _switchCamera,
                ),
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  elevation: 6,
                  onPressed: () => _leaveCall(endedByReason: 'citizen'),
                  child: const Icon(Icons.call_end, color: Colors.white, size: 30),
                ),
                IconButton(
                  icon: Icon(
                    _isVideoDisabled ? Icons.videocam_off : Icons.videocam,
                    color: _isVideoDisabled ? Colors.redAccent : Colors.white,
                    size: 28,
                  ),
                  onPressed: _toggleVideo,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}