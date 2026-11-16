import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'CameraScanPage.dart';

class DetailsPage extends StatelessWidget {
  final int learnerID;

  const DetailsPage({super.key, required this.learnerID});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Learner Details'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Photo'),
              Tab(text: 'POE'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const Center(child: Text('Photo Tab Content')),
            POETabContent(learnerID: learnerID),
          ],
        ),
      ),
    );
  }
}

class POETabContent extends StatefulWidget {
  final int learnerID;

  const POETabContent({super.key, required this.learnerID});

  @override
  _POETabContentState createState() => _POETabContentState();
}

class _POETabContentState extends State<POETabContent> {
  Map<String, dynamic> pathwaysData = {};
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchLearnerData();
  }

  Future<void> fetchLearnerData() async {
    final url = Uri.parse('http://192.168.68.160/New/lito/mobile/poe.php');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'learnerID': widget.learnerID.toString()},
      );

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        debugPrint('Decoded Response: $decodedResponse');

        // Debug print to check the response structure
        debugPrint('Pathways Data: ${decodedResponse['pathways']}');

        if (decodedResponse['pathways'] != null) {
          setState(() {
            pathwaysData = decodedResponse['pathways'];
            isLoading = false;
          });
        } else {
          throw Exception('No pathways data found');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Text(
          errorMessage!,
          style: const TextStyle(color: Colors.red, fontSize: 16),
        ),
      );
    }

    if (pathwaysData.isEmpty) {
      return const Center(
        child: Text(
          'No data found for this learner.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: pathwaysData.keys.length,
      itemBuilder: (context, index) {
        final pathwayName = pathwaysData.keys.elementAt(index);
        final qualifications = pathwaysData[pathwayName]['qualifications'];

        return ExpansionTile(
          title: Text(
            pathwayName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          children: qualifications.entries.map<Widget>((entry) {
            final qualificationName = entry.key;
            final unitStandards = entry.value['unitstandards'];

            return ExpansionTile(
              title: Text(
                qualificationName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              children: unitStandards.entries.map<Widget>((unitEntry) {
                final unitStandardName = unitEntry.key;
                final unitStandard = unitEntry.value;

                final summative = unitStandard['summative'] ?? [];
                final formative = unitStandard['formative'] ?? [];

                return ExpansionTile(
                  title: Text(
                    unitStandardName,
                    style: const TextStyle(fontSize: 13),
                  ),
                  children: [
                    if (summative.isNotEmpty)
                      ExpansionTile(
                        title: const Text('Summative'),
                        children: summative.map<Widget>((item) {
                          // Ensure that item['exercise'] is converted to a string
                          final exercise =
                              item['exercise']?.toString() ?? 'N/A';

                          return ListTile(
                            leading: const Icon(Icons.assignment),
                            title: Text('Summative: $exercise'),
                            trailing: IconButton(
                              icon: const Icon(Icons.camera_alt),
                              onPressed: () {
                                openCamera(context, 'Summative', exercise);
                              },
                            ),
                          );
                        }).toList(),
                      )
                    else
                      const ListTile(
                        title: Text('No summative data available'),
                      ),
                    if (formative.isNotEmpty)
                      ExpansionTile(
                        title: const Text('Formative'),
                        children: formative.map<Widget>((exercise) {
                          // Ensure that exercise is converted to a string
                          final exerciseStr = exercise?.toString() ?? 'N/A';

                          return ListTile(
                            leading: const Icon(Icons.book),
                            title: Text('Exercise: $exerciseStr'),
                            trailing: IconButton(
                              icon: const Icon(Icons.camera_alt),
                              onPressed: () {
                                openCamera(context, 'Formative', exerciseStr);
                              },
                            ),
                          );
                        }).toList(),
                      )
                    else
                      const ListTile(
                        title: Text('No formative data available'),
                      ),
                  ],
                );
              }).toList(),
            );
          }).toList(),
        );
      },
    );
  }

  void openCamera(BuildContext context, String type, String exercise) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScanPage(
          type: type,
          exercise: exercise,
          learnerID: widget.learnerID, // Accessing learnerID from the widget
        ),
      ),
    );

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result),
      ));
    }
  }
}
