import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'report_submission.dart';

class CameraPage extends StatefulWidget {
  final double? latitude;   // nullable
  final double? longitude;
  final bool isRetake;

  const CameraPage({
    super.key,
    this.latitude,
    this.longitude,
    this.isRetake = false,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  Timer? _videoTimer;
  int _secondsRecorded = 0;
  bool _isRecording = false;
  bool _isCompressing = false;

  @override
  void dispose() {
    _videoTimer?.cancel();
    super.dispose();
  }

  Future<CaptureRequest> _filePathBuilder(List<Sensor> sensors, String type, String extension) async {
    final directory = await getTemporaryDirectory();

    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final String dateString = '$year$month$day';

    final int randomIndex = Random().nextInt(900) + 100;
    final String fileName = '${dateString}_Reports_${type}_$randomIndex.$extension';

    final String filePath = p.join(directory.path, fileName);
    return SingleCaptureRequest(filePath, sensors.first);
  }

  // 🛡️ REBUILD-SAFE TIMER INITIALIZER
  void _startVideoTimeout(VideoRecordingCameraState state) {
    if (_isRecording) return; // Immediate guard against execution on widget rebuilds

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isRecording) return;

      setState(() {
        _isRecording = true;
        _secondsRecorded = 0;
      });

      _videoTimer?.cancel();
      _videoTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _secondsRecorded++;
        });

        if (_secondsRecorded >= 15) {
          timer.cancel();
          if (_isRecording) {
            await state.stopRecording();
            if (mounted) {
              setState(() => _isRecording = false);
            }
          }
        }
      });
    });
  }

  void _resetVideoState() {
    if (!_isRecording) return; // Prevents unnecessary post-frame callbacks when idle

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isRecording) return;
      _videoTimer?.cancel();
      setState(() {
        _isRecording = false;
        _secondsRecorded = 0;
      });
    });
  }

  Future<void> _navigateToReportSubmission(String filePath) async {
    String finalPath = filePath;
    final String extension = p.extension(filePath).toLowerCase();

    if (mounted) setState(() => _isCompressing = true);

    try {
      if (extension == '.jpg' || extension == '.jpeg' || extension == '.png') {
        // 🖼️ IMAGE COMPRESSION: Downscales captured image resolution to ~360p height (640x360)
        final String targetPath = filePath.replaceAll(
          extension,
          '_compressed$extension',
        );

        final XFile? compressedFile = await FlutterImageCompress.compressAndGetFile(
          filePath,
          targetPath,
          quality: 70,
          minWidth: 640,  // Target low resolution width
          minHeight: 360, // Target low resolution height
        );

        if (compressedFile != null) {
          finalPath = compressedFile.path;
          final originalFile = File(filePath);
          if (await originalFile.exists()) {
            await originalFile.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Compression error: $e');
    } finally {
      if (mounted) setState(() => _isCompressing = false);
    }

    final String customFileName = p.basename(finalPath);

    if (context.mounted) {
      if (widget.isRetake) {
        // 🎯 Retake flow: hand the new file back to the waiting
        // ReportSubmissionPage instead of creating a new one.
        Navigator.pop(context, {
          'path': finalPath,
          'fileName': customFileName,
        });
      } else {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReportSubmissionPage(
              localMediaPath: finalPath,
              mediaFileName: customFileName,
              latitude: widget.latitude,   // may be null
              longitude: widget.longitude,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return CameraAwesomeBuilder.awesome(
                saveConfig: SaveConfig.photoAndVideo(
                  initialCaptureMode: CaptureMode.photo,
                  photoPathBuilder: (sensors) => _filePathBuilder(sensors, 'image', 'jpg'),
                  videoPathBuilder: (sensors) => _filePathBuilder(sensors, 'video', 'mp4'),

                  // ⚡ LOW-RES HARDWARE RECORDING CONFIGURATION
                  videoOptions: VideoOptions(
                    enableAudio: true,
                    quality: VideoRecordingQuality.sd, // Moved quality here
                    android: AndroidVideoOptions(
                      fallbackStrategy: QualityFallbackStrategy.lower,
                      bitrate: 1000000, // 1 Mbps bitrate cap
                    ),
                    ios: CupertinoVideoOptions(
                      fps: 30,
                    ),
                  ),
                ),
                sensorConfig: SensorConfig.single(
                  sensor: Sensor.position(SensorPosition.back),
                  flashMode: FlashMode.none,
                  aspectRatio: CameraAspectRatios.ratio_16_9, // Standard video aspect ratio
                ),
                availableFilters: const [],
                previewFit: CameraPreviewFit.contain,

                onMediaTap: (mediaCapture) {
                  debugPrint('Gallery navigation explicitly suppressed.');
                },

                onMediaCaptureEvent: (event) {
                  event.captureRequest.when(
                    single: (singleRequest) {
                      if (singleRequest.file != null && event.status == MediaCaptureStatus.success) {
                        _navigateToReportSubmission(singleRequest.file!.path);
                      }
                    },
                    multiple: (multipleRequest) {
                      if (multipleRequest.fileBySensor.values.isNotEmpty && event.status == MediaCaptureStatus.success) {
                        final String? path = multipleRequest.fileBySensor.values.first?.path;
                        if (path != null) {
                          _navigateToReportSubmission(path);
                        }
                      }
                    },
                  );
                },

                // 🎨 DYNAMIC UI OVERLAY ELEMENTS
                topActionsBuilder: (state) {
                  if (state is VideoRecordingCameraState) {
                    _startVideoTimeout(state);
                  } else {
                    _resetVideoState();
                  }

                  return Container(
                    padding: EdgeInsets.only(
                      top: topPadding > 0 ? topPadding : 12,
                      left: 16,
                      right: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Close/Exit Viewfinder Button
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding: const EdgeInsets.all(8),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),

                        // Live Status Countdown Indicator Panel
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _isRecording
                              ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 8)
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '00:${_secondsRecorded.toString().padLeft(2, '0')} / 00:15',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: screenWidth > 600 ? 14 : 12,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          )
                              : const SizedBox.shrink(),
                        ),

                        // Spacer layout balance placeholder node
                        const SizedBox(width: 44),
                      ],
                    ),
                  );
                },
              );
            },
          ),

          // ⏳ LOADING OVERLAY DURING COMPRESSION
          if (_isCompressing)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFDC2626)),
                    SizedBox(height: 16),
                    Text(
                      'Optimizing media size...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}