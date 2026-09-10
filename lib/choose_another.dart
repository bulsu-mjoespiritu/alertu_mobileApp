import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

// FIXED IMPORTS: Pull type definitions safely
import 'package:flutter_nominatim/flutter_nominatim.dart' show Nominatim, Place;
import 'camera_page.dart';

class ChooseAnotherPage extends StatefulWidget {
  final Function(LatLng newLocation)? onLocationConfirmed;
  final LatLng initialLocation;

  /// When true, confirming just returns the pin to the caller (e.g. editing
  /// the location on an already-drafted report). When false (default), this
  /// page behaves as the first step of the original capture flow and pushes
  /// into [CameraPage] after confirming, since no photo/video has been taken yet.
  final bool isEditingExistingReport;

  const ChooseAnotherPage({
    super.key,
    required this.initialLocation,
    this.onLocationConfirmed,
    this.isEditingExistingReport = false,
  });

  @override
  State<ChooseAnotherPage> createState() => _ChooseAnotherPageState();
}

class _ChooseAnotherPageState extends State<ChooseAnotherPage> with SingleTickerProviderStateMixin {
  MapLibreMapController? _mapController;
  final TextEditingController _addressController = TextEditingController();
  final Nominatim _nominatim = Nominatim.instance;

  late LatLng _currentCenter;
  List<Place> _searchResults = [];
  bool _isLoadingSearch = false;
  bool _isDragging = false;
  Timer? _debounceTimer;

  late AnimationController _markerAnimController;
  late Animation<double> _markerScale;

  final Color primaryColor = const Color(0xff0d47a1);

  final LatLngBounds _bulacanBounds = LatLngBounds(
    southwest: const LatLng(14.7000, 120.6000),
    northeast: const LatLng(15.2000, 121.3000),
  );

  @override
  void initState() {
    super.initState();
    _currentCenter = widget.initialLocation;

    _markerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _markerScale = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _markerAnimController, curve: Curves.easeOutBack),
    );

    _determineLiveUserPosition();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _debounceTimer?.cancel();
    _markerAnimController.dispose();
    super.dispose();
  }

  Future<void> _determineLiveUserPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _reverseGeocode(_currentCenter);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _reverseGeocode(_currentCenter);
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      LatLng userCoords = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _currentCenter = userCoords;
        });
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(userCoords, 16.0),
        );
        _reverseGeocode(userCoords);
      }
    } catch (e) {
      debugPrint("Live GPS Lock fallback execution triggered: $e");
      _reverseGeocode(_currentCenter);
    }
  }

  Future<void> _reverseGeocode(LatLng coords) async {
    final String url = 'https://nominatim.openstreetmap.org/reverse'
        '?format=json'
        '&lat=${coords.latitude}'
        '&lon=${coords.longitude}'
        '&addressdetails=1';

    try {
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'com.example.alertu_flutter',
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final String displayName = data['display_name'] ?? 'Custom Coordinate Node';

        if (mounted) {
          setState(() {
            _addressController.text = displayName;
          });
        }
      }
    } catch (e) {
      debugPrint("Reverse geocoding connection error: $e");
    }
  }

  void _searchPlaces(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoadingSearch = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isLoadingSearch = true);

      try {
        final List<Place> rawResults = await _nominatim.search(query);

        final filteredResults = rawResults.where((place) {
          final double lat = place.latitude;
          final double lon = place.longitude;

          return lat >= _bulacanBounds.southwest.latitude &&
              lat <= _bulacanBounds.northeast.latitude &&
              lon >= _bulacanBounds.southwest.longitude &&
              lon <= _bulacanBounds.northeast.longitude;
        }).toList();

        if (mounted) {
          setState(() {
            _searchResults = filteredResults;
          });
        }
      } catch (e) {
        debugPrint("ChooseAnother geocoding error: $e");
      } finally { // 🎯 FIX: Changed 'final' to 'finally'
        if (mounted) {
          setState(() => _isLoadingSearch = false);
        }
      }
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  void _onCameraMove(CameraPosition position) {
    _currentCenter = position.target;
    if (!_isDragging) {
      setState(() => _isDragging = true);
      _markerAnimController.forward();
    }
  }

  void _onCameraIdle() {
    if (_isDragging) {
      setState(() => _isDragging = false);
      _markerAnimController.reverse();
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _reverseGeocode(_currentCenter);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
        ),
      ),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final bool isWideScreen = constraints.maxWidth > 650;
            final double containerWidth = isWideScreen ? 600 : constraints.maxWidth;

            return Stack(
              children: [
                // Locate this section in choose_another.dart (around lines 215-230)
                MapLibreMap(
                  styleString: 'https://tiles.openfreemap.org/styles/liberty',
                  initialCameraPosition: CameraPosition(
                    target: _currentCenter,
                    zoom: 15.5,
                  ),
                  // 🎯 FIX: Wrapped min and max zoom constraints into MinMaxZoomPreference
                  minMaxZoomPreference: const MinMaxZoomPreference(9.0, 18.0),
                  onMapCreated: _onMapCreated,
                  onCameraMove: _onCameraMove,
                  onCameraIdle: _onCameraIdle,
                  myLocationEnabled: false,
                  trackCameraPosition: true,
                ),

                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: ScaleTransition(
                        scale: _markerScale,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          transform: Matrix4.translationValues(0, _isDragging ? -10 : 0, 0),
                          child: Icon(
                            Icons.location_on_rounded,
                            color: Colors.red.shade700,
                            size: isWideScreen ? 58 : 48,
                            shadows: [
                              BoxShadow(
                                color: Colors.black.withOpacity(_isDragging ? 0.15 : 0.3),
                                blurRadius: _isDragging ? 12 : 6,
                                offset: Offset(0, _isDragging ? 15 : 4),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: containerWidth,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: TextField(
                              controller: _addressController,
                              onChanged: _searchPlaces,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                hintText: 'Type custom address location...',
                                hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w400),
                                prefixIcon: IconButton(
                                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                suffixIcon: _isLoadingSearch
                                    ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xff0d47a1))),
                                )
                                    : _addressController.text.isNotEmpty
                                    ? IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                                  onPressed: () {
                                    _addressController.clear();
                                    setState(() => _searchResults = []);
                                  },
                                )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),

                          if (_searchResults.isNotEmpty)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(top: 8),
                              constraints: const BoxConstraints(maxHeight: 240),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6))],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: _searchResults.length,
                                  separatorBuilder: (context, index) => Divider(height: 1, thickness: 1, color: Colors.grey.shade50),
                                  itemBuilder: (context, index) {
                                    final Place place = _searchResults[index];
                                    final String displayName = place.displayName;

                                    return ListTile(
                                      leading: Icon(Icons.location_on_outlined, color: Colors.grey.shade400, size: 20),
                                      title: Text(displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      onTap: () {
                                        final double lat = place.latitude;
                                        final double lon = place.longitude;
                                        final targetCoords = LatLng(lat, lon);

                                        setState(() {
                                          _currentCenter = targetCoords;
                                          _addressController.text = displayName;
                                          _searchResults = [];
                                        });

                                        FocusScope.of(context).unfocus();
                                        _mapController?.animateCamera(
                                          CameraUpdate.newLatLngZoom(targetCoords, 15.5),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: containerWidth,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ElevatedButton(
                        onPressed: () {
                          if (widget.onLocationConfirmed != null) {
                            widget.onLocationConfirmed!(_currentCenter);
                          }

                          if (widget.isEditingExistingReport) {
                            // 🎯 Editing an existing draft: only the pin changes.
                            // Don't force the user back into the camera.
                            Navigator.pop(context);
                          } else {
                            // Original "new report" flow: location is step 1,
                            // capturing the photo/video is step 2.
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CameraPage(
                                  latitude: _currentCenter.latitude,
                                  longitude: _currentCenter.longitude,
                                ),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 5,
                          shadowColor: primaryColor.withOpacity(0.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          widget.isEditingExistingReport
                              ? 'Update Location'
                              : 'Confirm Selected Location',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
