import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config.dart';

/// Debug page for testing Province/District/Municipality selection
class DebugLocationSelectionPage extends StatefulWidget {
  @override
  _DebugLocationSelectionPageState createState() => _DebugLocationSelectionPageState();
}

class _DebugLocationSelectionPageState extends State<DebugLocationSelectionPage> {
  List<String> _provinces = [];
  List<String> _districts = [];
  List<String> _municipalities = [];
  
  String? _selectedProvince;
  String? _selectedDistrict;
  String? _selectedMunicipality;
  
  String _debugLog = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchProvinces();
  }

  void _addToLog(String message) {
    setState(() {
      _debugLog += '[${DateTime.now().toLocal()}] $message\n';
    });
    print(message);
  }

  Future<void> _fetchProvinces() async {
    _addToLog('🏛️ Fetching provinces...');
    setState(() => _isLoading = true);
    
    try {
      final url = AppConfig.buildUrl('fetch_provinces.php');
      _addToLog('URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      
      _addToLog('Response status: ${response.statusCode}');
      _addToLog('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _provinces = List<String>.from(
              data['data']['provinces'].map((p) => p['name'] as String),
            );
          });
          _addToLog('✅ Provinces loaded: ${_provinces.length} items');
          _addToLog('Provinces: ${_provinces.join(', ')}');
        } else {
          _addToLog('❌ API returned success=false: ${data['message']}');
        }
      } else {
        _addToLog('❌ HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      _addToLog('❌ Error fetching provinces: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchDistricts(String province) async {
    _addToLog('🏘️ Fetching districts for province: $province');
    setState(() => _isLoading = true);
    
    try {
      final url = AppConfig.buildUrl('fetch_districts.php', queryParams: {'province': province});
      _addToLog('URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      
      _addToLog('Response status: ${response.statusCode}');
      _addToLog('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _districts = List<String>.from(
              data['data']['districts'].map((d) => d['name'] as String),
            );
            _municipalities = []; // Clear municipalities
            _selectedDistrict = null;
            _selectedMunicipality = null;
          });
          _addToLog('✅ Districts loaded: ${_districts.length} items');
          _addToLog('Districts: ${_districts.join(', ')}');
        } else {
          _addToLog('❌ API returned success=false: ${data['message']}');
          setState(() {
            _districts = [];
            _municipalities = [];
          });
        }
      } else {
        _addToLog('❌ HTTP error: ${response.statusCode}');
        setState(() {
          _districts = [];
          _municipalities = [];
        });
      }
    } catch (e) {
      _addToLog('❌ Error fetching districts: $e');
      setState(() {
        _districts = [];
        _municipalities = [];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMunicipalities(String district) async {
    _addToLog('🏢 Fetching municipalities for district: $district');
    setState(() => _isLoading = true);
    
    try {
      final url = AppConfig.buildUrl('fetch_municipalities.php', queryParams: {'district': district});
      _addToLog('URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      
      _addToLog('Response status: ${response.statusCode}');
      _addToLog('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _municipalities = List<String>.from(
              data['data']['municipalities'].map((m) => m['name'] as String),
            );
            _selectedMunicipality = null;
          });
          _addToLog('✅ Municipalities loaded: ${_municipalities.length} items');
          _addToLog('Municipalities: ${_municipalities.join(', ')}');
        } else {
          _addToLog('❌ API returned success=false: ${data['message']}');
          setState(() {
            _municipalities = [];
          });
        }
      } else {
        _addToLog('❌ HTTP error: ${response.statusCode}');
        setState(() {
          _municipalities = [];
        });
      }
    } catch (e) {
      _addToLog('❌ Error fetching municipalities: $e');
      setState(() {
        _municipalities = [];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Debug Location Selection'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Loading indicator
            if (_isLoading) 
              LinearProgressIndicator(),
              
            SizedBox(height: 16),
            
            // Province dropdown
            DropdownButtonFormField<String>(
              value: _selectedProvince,
              decoration: InputDecoration(
                labelText: 'Province',
                border: OutlineInputBorder(),
              ),
              items: _provinces.map((province) {
                return DropdownMenuItem<String>(
                  value: province,
                  child: Text(province),
                );
              }).toList(),
              onChanged: (String? newValue) async {
                if (newValue != null) {
                  setState(() {
                    _selectedProvince = newValue;
                    _selectedDistrict = null;
                    _selectedMunicipality = null;
                  });
                  await _fetchDistricts(newValue);
                }
              },
            ),
            
            SizedBox(height: 16),
            
            // District dropdown
            DropdownButtonFormField<String>(
              value: _selectedDistrict,
              decoration: InputDecoration(
                labelText: 'District (${_districts.length} available)',
                border: OutlineInputBorder(),
              ),
              items: _districts.map((district) {
                return DropdownMenuItem<String>(
                  value: district,
                  child: Text(district),
                );
              }).toList(),
              onChanged: _districts.isEmpty ? null : (String? newValue) async {
                if (newValue != null) {
                  setState(() {
                    _selectedDistrict = newValue;
                    _selectedMunicipality = null;
                  });
                  await _fetchMunicipalities(newValue);
                }
              },
            ),
            
            SizedBox(height: 16),
            
            // Municipality dropdown
            DropdownButtonFormField<String>(
              value: _selectedMunicipality,
              decoration: InputDecoration(
                labelText: 'Municipality (${_municipalities.length} available)',
                border: OutlineInputBorder(),
              ),
              items: _municipalities.map((municipality) {
                return DropdownMenuItem<String>(
                  value: municipality,
                  child: Text(municipality),
                );
              }).toList(),
              onChanged: _municipalities.isEmpty ? null : (String? newValue) {
                setState(() {
                  _selectedMunicipality = newValue;
                });
              },
            ),
            
            SizedBox(height: 16),
            
            // Current selection display
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Selection:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Province: ${_selectedProvince ?? "Not selected"}'),
                  Text('District: ${_selectedDistrict ?? "Not selected"}'),
                  Text('Municipality: ${_selectedMunicipality ?? "Not selected"}'),
                ],
              ),
            ),
            
            SizedBox(height: 16),
            
            // Debug log
            Expanded(
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Debug Log:',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          _debugLog.isEmpty ? 'No debug information yet...' : _debugLog,
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Clear log button
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _debugLog = '';
                });
              },
              child: Text('Clear Log'),
            ),
          ],
        ),
      ),
    );
  }
}