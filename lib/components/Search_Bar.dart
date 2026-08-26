import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

class MapSearchBar extends StatefulWidget {
  final LatLngBounds searchBounds;
  final Function(LatLng coordinates, String displayName) onPlaceSelected;
  final VoidCallback? onClear;

  const MapSearchBar({
    super.key,
    required this.searchBounds,
    required this.onPlaceSelected,
    this.onClear,
  });

  @override
  State<MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchResult {
  final LatLng coordinates;
  final String displayName;

  const _MapSearchResult({
    required this.coordinates,
    required this.displayName,
  });
}

class _MapSearchBarState extends State<MapSearchBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounceTimer;
  int _requestSequence = 0;
  List<_MapSearchResult> _searchResults = const [];
  bool _isLoadingSearch = false;
  bool _hasSearchError = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _addressController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _searchPlaces(String rawQuery) {
    _debounceTimer?.cancel();
    final query = rawQuery.trim();
    final requestId = ++_requestSequence;

    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _isLoadingSearch = false;
        _hasSearchError = false;
      });
      widget.onClear?.call();
      return;
    }

    setState(() {
      _isLoadingSearch = true;
      _hasSearchError = false;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 420), () async {
      try {
        final results = await _queryPhoton(query);
        if (!mounted || requestId != _requestSequence) return;

        setState(() {
          _searchResults = results;
          _isLoadingSearch = false;
        });
      } catch (error) {
        debugPrint('Map search error: $error');
        if (!mounted || requestId != _requestSequence) return;

        setState(() {
          _searchResults = const [];
          _isLoadingSearch = false;
          _hasSearchError = true;
        });
      }
    });
  }

  Future<List<_MapSearchResult>> _queryPhoton(String query) async {
    // Keep the request broadly compatible with the public Photon instance.
    // Results are still restricted to the current map area below by
    // _isInsideSearchBounds(), so no bbox is required in the network request.
    final uri = Uri.https(
      'photon.komoot.io',
      '/api/',
      <String, String>{
        'q': query,
        'limit': '8',
        'countrycode': 'PH',
      },
    );

    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'AlertU/1.0 (map search)',
      },
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('Photon response ${response.statusCode}: ${response.body}');
      throw Exception('Photon returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return const [];
    final features = decoded['features'];
    if (features is! List) return const [];

    final results = <_MapSearchResult>[];
    for (final feature in features) {
      if (feature is! Map) continue;
      final geometry = feature['geometry'];
      final rawCoordinates = geometry is Map ? geometry['coordinates'] : null;
      if (rawCoordinates is! List || rawCoordinates.length < 2) continue;

      // Photon GeoJSON coordinates are [longitude, latitude].
      final lon = double.tryParse('${rawCoordinates[0]}');
      final lat = double.tryParse('${rawCoordinates[1]}');
      if (lat == null || lon == null) continue;

      final rawProperties = feature['properties'];
      final properties = rawProperties is Map
          ? rawProperties
          : const <String, dynamic>{};

      String property(String key) => '${properties[key] ?? ''}'.trim();

      final displayParts = <String>[
        property('name'),
        property('housenumber'),
        property('street'),
        property('district'),
        property('city'),
        property('state'),
        property('postcode'),
        property('country'),
      ].where((part) => part.isNotEmpty).toList();

      final displayName = displayParts.join(', ');
      if (displayName.isEmpty) continue;

      final coordinates = LatLng(lat, lon);
      if (!_isInsideSearchBounds(coordinates)) continue;
      results.add(_MapSearchResult(
        coordinates: coordinates,
        displayName: displayName,
      ));
    }
    return results;
  }

  bool _isInsideSearchBounds(LatLng coordinates) {
    return coordinates.latitude >= widget.searchBounds.southwest.latitude &&
        coordinates.latitude <= widget.searchBounds.northeast.latitude &&
        coordinates.longitude >= widget.searchBounds.southwest.longitude &&
        coordinates.longitude <= widget.searchBounds.northeast.longitude;
  }

  void _selectResult(_MapSearchResult result) {
    _debounceTimer?.cancel();
    _requestSequence++;
    _addressController.text = result.displayName;
    setState(() {
      _searchResults = const [];
      _isLoadingSearch = false;
      _hasSearchError = false;
    });
    _focusNode.unfocus();
    widget.onPlaceSelected(result.coordinates, result.displayName);
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _requestSequence++;
    _addressController.clear();
    _focusNode.unfocus();
    setState(() {
      _searchResults = const [];
      _isLoadingSearch = false;
      _hasSearchError = false;
    });
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final primaryText = isDark ? Colors.white : const Color(0xFF212121);
    final secondaryText = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final hintColor = isDark ? Colors.grey.shade500 : Colors.grey.shade400;
    final dividerColor = isDark ? const Color(0xFF334155) : Colors.grey.shade100;
    final shadowColor = isDark
        ? Colors.black.withOpacity(0.32)
        : Colors.black.withOpacity(0.08);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(30),
            border: isDark
                ? Border.all(color: const Color(0xFF334155), width: 1)
                : null,
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: _focusNode.hasFocus ? 14 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: _addressController,
            focusNode: _focusNode,
            onSubmitted: (_) {
              if (_searchResults.isNotEmpty) _selectResult(_searchResults.first);
            },
            onChanged: _searchPlaces,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: primaryText,
            ),
            decoration: InputDecoration(
              hintText: 'Search places or addresses...',
              hintStyle: TextStyle(
                color: hintColor,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(Icons.search_rounded, color: secondaryText),
              suffixIcon: _isLoadingSearch
                  ? const Padding(
                padding: EdgeInsets.all(12),
                child: _SearchShimmer(size: 20),
              )
                  : _addressController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.close_rounded, color: secondaryText),
                onPressed: _clearSearch,
              )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: _isLoadingSearch
              ? _SearchResultsShimmer(
            background: cardBg,
            shimmerBase: isDark
                ? const Color(0xFF29384D)
                : const Color(0xFFF1F3F5),
          )
              : _hasSearchError
              ? _SearchMessage(
            background: cardBg,
            textColor: secondaryText,
            icon: Icons.cloud_off_rounded,
            message: 'Search is temporarily unavailable',
          )
              : _searchResults.isEmpty
              ? const SizedBox.shrink()
              : _SearchResultsList(
            results: _searchResults,
            background: cardBg,
            primaryText: primaryText,
            secondaryText: secondaryText,
            dividerColor: dividerColor,
            onSelected: _selectResult,
          ),
        ),
      ],
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  final List<_MapSearchResult> results;
  final Color background;
  final Color primaryText;
  final Color secondaryText;
  final Color dividerColor;
  final ValueChanged<_MapSearchResult> onSelected;

  const _SearchResultsList({
    required this.results,
    required this.background,
    required this.primaryText,
    required this.secondaryText,
    required this.dividerColor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: results.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: dividerColor,
          ),
          itemBuilder: (context, index) {
            final result = results[index];
            return ListTile(
              dense: true,
              leading: Icon(
                Icons.location_on_outlined,
                color: secondaryText,
                size: 20,
              ),
              title: Text(
                result.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: primaryText,
                ),
              ),
              onTap: () => onSelected(result),
            );
          },
        ),
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  final Color background;
  final Color textColor;
  final IconData icon;
  final String message;

  const _SearchMessage({
    required this.background,
    required this.textColor,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultsShimmer extends StatefulWidget {
  final Color background;
  final Color shimmerBase;

  const _SearchResultsShimmer({
    required this.background,
    required this.shimmerBase,
  });

  @override
  State<_SearchResultsShimmer> createState() => _SearchResultsShimmerState();
}

class _SearchResultsShimmerState extends State<_SearchResultsShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ShaderMask(
            shaderCallback: (bounds) {
              final progress = (_controller.value * 2) - 0.5;
              return LinearGradient(
                begin: Alignment(-1.0 + progress, 0),
                end: Alignment(progress, 0),
                colors: [
                  widget.shimmerBase.withOpacity(0.45),
                  widget.shimmerBase.withOpacity(0.95),
                  widget.shimmerBase.withOpacity(0.45),
                ],
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcATop,
            child: Column(
              children: List.generate(
                3,
                    (index) => Padding(
                  padding: EdgeInsets.only(bottom: index == 2 ? 0 : 12),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchShimmer extends StatefulWidget {
  final double size;

  const _SearchShimmer({required this.size});

  @override
  State<_SearchShimmer> createState() => _SearchShimmerState();
}

class _SearchShimmerState extends State<_SearchShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final progress = (_controller.value * 2) - 0.5;
            return LinearGradient(
              begin: Alignment(-1.0 + progress, 0),
              end: Alignment(progress, 0),
              colors: const [
                Colors.white38,
                Colors.white,
                Colors.white38,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: Icon(
            Icons.search_rounded,
            size: widget.size,
            color: Colors.white,
          ),
        );
      },
    );
  }
}

// Homepage integration:
//
// MapSearchBar(
//   searchBounds: _bulacanBounds,
//   onPlaceSelected: (coordinates, displayName) async {
//     if (mapController == null) return;
//     await mapController!.animateCamera(
//       CameraUpdate.newLatLngZoom(coordinates, 16.0),
//       duration: const Duration(milliseconds: 850),
//     );
//   },
//   onClear: () {
//     // Keep the current map position; only dismiss the results.
//   },
// )
//
// The callback should be placed where Homepage currently builds MapSearchBar.
// MapLibre supplies the map camera and LatLng types; Nominatim supplies the
// place results, filtered to the Homepage search bounds above.
