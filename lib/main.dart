import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'splash_screen.dart';
import 'device_details_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'B-Connect',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        cardColor: const Color(0xFF1E1E1E),
        primaryColor: Colors.blue,
        colorScheme: const ColorScheme.dark(
          primary: Colors.blue,
          secondary: Colors.blueAccent,
          surface: Color(0xFF1E1E1E),
          background: Color(0xFF0A0A0A),
          error: Colors.red,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onBackground: Colors.white,
          onError: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum SortOption { rssi, name, time }

class _ScannerScreenState extends State<ScannerScreen>
    with TickerProviderStateMixin {
  List<ScanResult> _scanResults = [];
  List<ScanResult> _filteredResults = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _rippleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  // Search and filter
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  SortOption _sortOption = SortOption.rssi;
  bool _showFavoritesOnly = false;

  // Favorites
  Set<String> _favorites = {};
  final String _favoritesKey = 'favorites_set';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadFavorites();

    // Pulse animation for scanning icon
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Rotation animation for scanning icon
    _rotationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );

    // Ripple animation for scan button
    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _stopScan();
    _searchController.dispose();
    _pulseController.dispose();
    _rotationController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesList = prefs.getStringList(_favoritesKey) ?? [];
    setState(() {
      _favorites = favoritesList.toSet();
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favorites.toList());
  }

  void _toggleFavorite(String deviceId) {
    setState(() {
      if (_favorites.contains(deviceId)) {
        _favorites.remove(deviceId);
      } else {
        _favorites.add(deviceId);
      }
    });
    _saveFavorites();
    HapticFeedback.lightImpact();
  }

  bool _isFavorite(String deviceId) {
    return _favorites.contains(deviceId);
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _applyFilters();
    });
  }

  void _applyFilters() {
    _filteredResults = List.from(_scanResults);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      _filteredResults = _filteredResults.where((result) {
        final name = result.advertisementData.advName.toLowerCase();
        final deviceId = result.device.remoteId.str.toLowerCase();
        return name.contains(_searchQuery) || deviceId.contains(_searchQuery);
      }).toList();
    }

    // Apply favorites filter
    if (_showFavoritesOnly) {
      _filteredResults = _filteredResults.where((result) {
        return _isFavorite(result.device.remoteId.str);
      }).toList();
    }

    // Apply sorting
    switch (_sortOption) {
      case SortOption.rssi:
        _filteredResults.sort((a, b) => b.rssi.compareTo(a.rssi));
        break;
      case SortOption.name:
        _filteredResults.sort((a, b) {
          final nameA = a.advertisementData.advName.isEmpty
              ? 'N/A'
              : a.advertisementData.advName;
          final nameB = b.advertisementData.advName.isEmpty
              ? 'N/A'
              : b.advertisementData.advName;
          return nameA.compareTo(nameB);
        });
        break;
      case SortOption.time:
        // Keep original order (most recent first)
        break;
    }
  }

  Future<void> _requestPermissions() async {
    // Request Bluetooth permissions
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
    await Permission.locationWhenInUse.request();

    // Check if Bluetooth is available
    if (await FlutterBluePlus.isSupported == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth is not supported on this device'),
          ),
        );
      }
      return;
    }
  }

  void _startScan() async {
    if (_isScanning) return;

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Check Bluetooth state
    BluetoothAdapterState adapterState =
        await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable Bluetooth')),
        );
      }
      return;
    }

    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    // Start animations
    _pulseController.repeat(reverse: true);
    _rotationController.repeat();
    _rippleController.repeat();

    // Start scanning
    _scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        if (mounted) {
          setState(() {
            // Filter for non-connectable devices only
            final filteredResults = results
                .where((result) => !result.advertisementData.connectable)
                .toList();

            // Remove duplicates based on device ID, keeping the one with strongest signal
            final deviceMap = <String, ScanResult>{};
            for (var result in filteredResults) {
              final deviceId = result.device.remoteId.str;
              if (!deviceMap.containsKey(deviceId) ||
                  deviceMap[deviceId]!.rssi < result.rssi) {
                deviceMap[deviceId] = result;
              }
            }

            _scanResults = deviceMap.values.toList();
            _applyFilters();
          });
        }
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Scan error: $error')));
          setState(() {
            _isScanning = false;
          });
        }
      },
    );

    // Listen for scan completion
    FlutterBluePlus.isScanning.listen((isScanning) {
      if (mounted && !isScanning) {
        setState(() {
          _isScanning = false;
        });
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: false,
    );
  }

  void _stopScan() {
    // Haptic feedback
    HapticFeedback.mediumImpact();

    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = false;
    });

    // Stop animations
    _pulseController.stop();
    _rotationController.stop();
    _rippleController.stop();
    _pulseController.reset();
    _rotationController.reset();
    _rippleController.reset();
  }

  Color _getBluetoothIconColor(int index) {
    final colors = [
      Colors.lightBlue,
      Colors.green,
      Colors.yellow,
      Colors.orange,
      Colors.pink,
      Colors.purple,
    ];
    return colors[index % colors.length];
  }

  String _formatRssi(int rssi) {
    return '$rssi dBm';
  }

  String _formatManufacturerData(Map<int, List<int>> manufacturerData) {
    if (manufacturerData.isEmpty) return '';

    final entries = manufacturerData.entries.toList();
    if (entries.isEmpty) return '';

    final key = entries.first.key;

    // Check for common manufacturer IDs
    String manufacturerName = 'Unknown';
    if (key == 0x004C) {
      manufacturerName = 'Apple';
    } else if (key == 0x0006) {
      manufacturerName = 'Microsoft';
    } else if (key == 0x000F) {
      manufacturerName = 'Broadcom';
    } else if (key == 0xFFFF) {
      manufacturerName = 'Bluetooth SIG Specification';
    }

    return 'Manufacturer Data: $manufacturerName';
  }

  List<String> _formatDetailedManufacturerData(
    Map<int, List<int>> manufacturerData,
  ) {
    if (manufacturerData.isEmpty) return [];

    final entries = manufacturerData.entries.toList();
    if (entries.isEmpty) return [];

    final key = entries.first.key;
    final value = entries.first.value;

    List<String> details = [];

    // Try to parse as iBeacon or Eddystone if possible
    if (key == 0x004C && value.length >= 23) {
      // Apple iBeacon format
      if (value[0] == 0x02 && value[1] == 0x15) {
        // iBeacon detected
        final uuid = value
            .sublist(2, 18)
            .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
            .toList();
        final major = (value[18] << 8) | value[19];
        final minor = (value[20] << 8) | value[21];
        final txPower = value[22];

        String uuidStr = '';
        for (int i = 0; i < uuid.length; i++) {
          if (i == 4 || i == 6 || i == 8 || i == 10) uuidStr += '-';
          uuidStr += uuid[i];
        }

        details.add('UUID: $uuidStr');
        details.add('Major: $major, Minor: $minor');
        details.add('Tx Power: $txPower dBm');
      }
    }

    // If no specific format detected, show raw data
    if (details.isEmpty && value.isNotEmpty) {
      // Show first few bytes as hex
      final displayBytes = value.length > 8 ? value.sublist(0, 8) : value;
      final hexDisplay = displayBytes
          .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
          .join(' ');
      if (value.length > 8) {
        details.add('Data: $hexDisplay...');
      } else {
        details.add('Data: $hexDisplay');
      }
    }

    return details;
  }

  Widget _buildSignalStrengthBars(int rssi) {
    int bars;
    Color barColor;

    if (rssi >= -50) {
      bars = 3;
      barColor = Colors.blue;
    } else if (rssi >= -70) {
      bars = 3;
      barColor = Colors.yellow;
    } else if (rssi >= -85) {
      bars = 2;
      barColor = Colors.yellow;
    } else {
      bars = 1;
      barColor = Colors.grey;
    }

    return Row(
      children: List.generate(3, (index) {
        return Container(
          width: 5,
          height: (index + 1) * 6.0 + 2,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: index < bars ? barColor : Colors.grey.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildDeviceCard(ScanResult result, int index) {
    final advData = result.advertisementData;
    final deviceName = advData.advName.isEmpty ? 'N/A' : advData.advName;
    final deviceId = result.device.remoteId.str;
    final rssi = result.rssi;
    final txPower = advData.txPowerLevel;
    final manufacturerData = advData.manufacturerData;
    final serviceData = advData.serviceData;
    final isFavorite = _isFavorite(deviceId);

    // Calculate connection time (simulated - in real app you'd track this)
    final connectionTime = '${(100 + index * 50).toStringAsFixed(2)} ms';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DeviceDetailsPage(
                scanResult: result,
                isFavorite: isFavorite,
                onFavoriteToggle: () => _toggleFavorite(deviceId),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getBluetoothIconColor(index),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.bluetooth,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  deviceName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  _toggleFavorite(deviceId);
                                },
                                child: Icon(
                                  isFavorite ? Icons.star : Icons.star_border,
                                  color: isFavorite
                                      ? Colors.amber
                                      : Colors.grey,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          if (txPower != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Tx Power: $txPower dBm',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (advData.connectable) ...[
                      ElevatedButton(
                        onPressed: null, // Disabled for non-connectable devices
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[800],
                          disabledForegroundColor: Colors.white,
                        ),
                        child: const Text('Connect'),
                      ),
                    ],
                  ],
                ),
                if (manufacturerData.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _formatManufacturerData(manufacturerData),
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                  ..._formatDetailedManufacturerData(manufacturerData).map(
                    (detail) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        detail,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),
                  ),
                ],
                if (serviceData.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ...serviceData.entries.map((entry) {
                    final uuid = entry.key.toString();
                    final data = entry.value;
                    final hexData = data
                        .map(
                          (b) =>
                              b.toRadixString(16).toUpperCase().padLeft(2, '0'),
                        )
                        .join(' ');
                    return Text(
                      'Service: $uuid - $hexData',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    );
                  }),
                ],
                // Show additional data if available
                if (advData.serviceUuids.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Services: ${advData.serviceUuids.length}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildSignalStrengthBars(rssi),
                    const SizedBox(width: 8),
                    Text(
                      _formatRssi(rssi),
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.swap_horiz, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      connectionTime,
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedScanningIcon() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _rotationAnimation]),
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Transform.rotate(
            angle: _rotationAnimation.value * 2 * 3.14159,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.1),
                border: Border.all(
                  color: Colors.blue.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.bluetooth_searching,
                size: 64,
                color: Colors.blue.withOpacity(0.8),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPulsingRipple() {
    return AnimatedBuilder(
      animation: _rippleController,
      builder: (context, child) {
        return Container(
          width: 80 + (_rippleController.value * 40),
          height: 80 + (_rippleController.value * 40),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.blue.withOpacity(1 - _rippleController.value),
              width: 2,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'B-Connect',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _showFavoritesOnly
                                  ? Icons.star
                                  : Icons.star_border,
                              color: _showFavoritesOnly
                                  ? Colors.amber
                                  : Colors.white,
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _showFavoritesOnly = !_showFavoritesOnly;
                                _applyFilters();
                              });
                            },
                            tooltip: 'Show favorites only',
                          ),
                          PopupMenuButton<SortOption>(
                            icon: const Icon(Icons.sort, color: Colors.white),
                            tooltip: 'Sort options',
                            onSelected: (SortOption option) {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _sortOption = option;
                                _applyFilters();
                              });
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: SortOption.rssi,
                                child: Row(
                                  children: [
                                    Icon(Icons.signal_cellular_alt, size: 20),
                                    SizedBox(width: 8),
                                    Text('Signal Strength'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: SortOption.name,
                                child: Row(
                                  children: [
                                    Icon(Icons.sort_by_alpha, size: 20),
                                    SizedBox(width: 8),
                                    Text('Name'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: SortOption.time,
                                child: Row(
                                  children: [
                                    Icon(Icons.access_time, size: 20),
                                    SizedBox(width: 8),
                                    Text('Time Discovered'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Search bar
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search devices...',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.withOpacity(0.1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey.withOpacity(0.1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Device List
            Expanded(
              child: _scanResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isScanning) ...[
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                _buildPulsingRipple(),
                                _buildAnimatedScanningIcon(),
                              ],
                            ),
                          ] else ...[
                            Icon(
                              Icons.bluetooth_searching,
                              size: 64,
                              color: Colors.grey[600],
                            ),
                          ],
                          const SizedBox(height: 24),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              _isScanning
                                  ? 'Scanning for devices...'
                                  : 'No devices found\nTap scan to start',
                              key: ValueKey(_isScanning),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        if (!_isScanning) {
                          HapticFeedback.mediumImpact();
                          _startScan();
                        }
                        await Future.delayed(const Duration(seconds: 1));
                      },
                      color: Colors.blue,
                      child: _filteredResults.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off,
                                    size: 64,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No devices match your search',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _filteredResults.length,
                              itemBuilder: (context, index) {
                                return AnimatedContainer(
                                  duration: Duration(
                                    milliseconds: 300 + (index * 50),
                                  ),
                                  curve: Curves.easeOut,
                                  child: _buildDeviceCard(
                                    _filteredResults[index],
                                    index,
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),

      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return ScaleTransition(scale: animation, child: child);
        },
        child: FloatingActionButton.extended(
          key: ValueKey(_isScanning),
          onPressed: _isScanning ? _stopScan : _startScan,
          backgroundColor: _isScanning ? Colors.red : Colors.blue,
          icon: Icon(_isScanning ? Icons.stop : Icons.search),
          label: Text(_isScanning ? 'Stop' : 'Scan'),
        ),
      ),
    );
  }
}
