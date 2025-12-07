import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'constants.dart';

class DeviceDetailsPage extends StatefulWidget {
  final ScanResult scanResult;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;

  const DeviceDetailsPage({
    super.key,
    required this.scanResult,
    required this.isFavorite,
    required this.onFavoriteToggle,
  });

  @override
  State<DeviceDetailsPage> createState() => _DeviceDetailsPageState();
}

class _DeviceDetailsPageState extends State<DeviceDetailsPage> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
  }

  @override
  void didUpdateWidget(DeviceDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFavorite != widget.isFavorite) {
      setState(() {
        _isFavorite = widget.isFavorite;
      });
    }
  }

  void _toggleFavorite() {
    setState(() {
      _isFavorite = !_isFavorite;
    });
    widget.onFavoriteToggle();
  }

  String _formatManufacturerData(Map<int, List<int>> manufacturerData) {
    if (manufacturerData.isEmpty) return '';

    final entries = manufacturerData.entries.toList();
    if (entries.isEmpty) return '';

    final key = entries.first.key;

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

    return manufacturerName;
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

    if (key == 0x004C && value.length >= 23) {
      if (value[0] == 0x02 && value[1] == 0x15) {
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

    if (details.isEmpty && value.isNotEmpty) {
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

  Widget _buildInfoCard(String title, String value, {IconData? icon}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.blue, size: 24),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalStrengthIndicator(int rssi) {
    int bars;
    Color barColor;
    String strength;

    if (rssi >= -50) {
      bars = 4;
      barColor = Colors.green;
      strength = 'Excellent';
    } else if (rssi >= -60) {
      bars = 4;
      barColor = Colors.blue;
      strength = 'Very Good';
    } else if (rssi >= -70) {
      bars = 3;
      barColor = Colors.yellow;
      strength = 'Good';
    } else if (rssi >= -85) {
      bars = 2;
      barColor = Colors.orange;
      strength = 'Fair';
    } else {
      bars = 1;
      barColor = Colors.red;
      strength = 'Weak';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Signal Strength',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                strength,
                style: TextStyle(
                  fontSize: 14,
                  color: barColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ...List.generate(4, (index) {
                return Container(
                  width: 8,
                  height: (index + 1) * 8.0 + 4,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: index < bars
                        ? barColor
                        : Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
              const SizedBox(width: 16),
              Text(
                '$rssi dBm',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final advData = widget.scanResult.advertisementData;
    final deviceName = advData.advName.isEmpty
        ? 'Unknown Device'
        : advData.advName;
    final deviceId = widget.scanResult.device.remoteId.str;
    final rssi = widget.scanResult.rssi;
    final txPower = advData.txPowerLevel;
    final manufacturerData = advData.manufacturerData;
    final serviceData = advData.serviceData;

    final hasUrl = Constants.urlMapperList.any(
      (urlMapper) => urlMapper.title == deviceName,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Device Details',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.star : Icons.star_border,
              color: _isFavorite ? Colors.amber : Colors.white,
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              _toggleFavorite();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bluetooth,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    deviceName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (hasUrl) ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        final urlMapper = Constants.urlMapperList.firstWhere(
                          (urlMapper) => urlMapper.title == deviceName,
                        );
                        launchUrl(Uri.parse(urlMapper.url));
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open URL'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Signal Strength
            _buildSignalStrengthIndicator(rssi),

            // Basic Information
            _buildInfoCard('Device ID', deviceId, icon: Icons.fingerprint),
            if (txPower != null)
              _buildInfoCard(
                'Tx Power',
                '$txPower dBm',
                icon: Icons.signal_cellular_alt,
              ),
            _buildInfoCard(
              'Connectable',
              advData.connectable ? 'Yes' : 'No',
              icon: Icons.link,
            ),

            // Manufacturer Data
            if (manufacturerData.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Manufacturer Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              _buildInfoCard(
                'Manufacturer',
                _formatManufacturerData(manufacturerData),
                icon: Icons.business,
              ),
              ..._formatDetailedManufacturerData(manufacturerData).map(
                (detail) => Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    detail,
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ),
              ),
            ],

            // Service Data
            if (serviceData.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Service Data',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              ...serviceData.entries.map((entry) {
                final uuid = entry.key.toString();
                final data = entry.value;
                final hexData = data
                    .map(
                      (b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'),
                    )
                    .join(' ');
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UUID: $uuid',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hexData,
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                );
              }),
            ],

            // Service UUIDs
            if (advData.serviceUuids.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Service UUIDs',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              ...advData.serviceUuids.map((uuid) {
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    uuid.toString(),
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                );
              }),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
