import 'package:beacon_scanner/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beacon Scanner',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
      ),
      home: const ScannerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
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

            // Sort by RSSI (strongest first)
            _scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
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
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = false;
    });
  }

  @override
  void dispose() {
    _stopScan();
    super.dispose();
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
    final rssi = result.rssi;
    final txPower = advData.txPowerLevel;
    final manufacturerData = advData.manufacturerData;
    final serviceData = advData.serviceData;

    // Calculate connection time (simulated - in real app you'd track this)
    final connectionTime = '${(100 + index * 50).toStringAsFixed(2)} ms';

    return InkWell(
      onTap: () {
        if (Constants.urlMapperList.any((urlMapper) => urlMapper.title == deviceName)) {
          final urlMapper = Constants.urlMapperList.firstWhere((urlMapper) => urlMapper.title == deviceName);
          launchUrl(Uri.parse(urlMapper.url));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Beacon not found')));
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFF1E1E1E),
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
                        Text(
                          deviceName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
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
                  const Text(
                    'Beacon Scanner',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
                          Icon(
                            Icons.bluetooth_searching,
                            size: 64,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isScanning
                                ? 'Scanning for devices...'
                                : 'No devices found\nTap scan to start',
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
                      itemCount: _scanResults.length,
                      itemBuilder: (context, index) {
                        return _buildDeviceCard(_scanResults[index], index);
                      },
                    ),
            ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? _stopScan : _startScan,
        backgroundColor: Colors.blue,
        child: Icon(_isScanning ? Icons.stop : Icons.search),
      ),
    );
  }
}
