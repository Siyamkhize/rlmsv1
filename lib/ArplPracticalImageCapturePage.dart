import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

class ArplPracticalImageCapturePage extends StatefulWidget {
  final int learnerID;
  final int classID;
  final String ofoNumber;
  final String role; // 'assessor' or 'moderator'
  final String userId;

  const ArplPracticalImageCapturePage({
    super.key,
    required this.learnerID,
    required this.classID,
    required this.ofoNumber,
    required this.role,
    required this.userId,
  });

  @override
  _ArplPracticalImageCapturePageState createState() =>
      _ArplPracticalImageCapturePageState();
}

class _ArplPracticalImageCapturePageState
    extends State<ArplPracticalImageCapturePage> {
  final ImagePicker _imagePicker = ImagePicker();
  final Map<String, List<Map<String, dynamic>>> _practicalImages = {};
  bool _isLoading = false;
  bool _isSaving = false;

  final List<Map<String, String>> _practicalTasks = [
    {'id': 'PT1', 'name': 'Practical Task 1'},
    {'id': 'PT2', 'name': 'Practical Task 2'},
    {'id': 'PT3', 'name': 'Practical Task 3'},
    {'id': 'PT4', 'name': 'Practical Task 4'},
    {'id': 'PT5', 'name': 'Practical Task 5'},
    {'id': 'PT6', 'name': 'Practical Task 6'},
    {'id': 'PT7', 'name': 'Practical Task 7'},
    {'id': 'PT8', 'name': 'Practical Task 8'},
    {'id': 'PT9', 'name': 'Practical Task 9'},
    {'id': 'PT10', 'name': 'Practical Task 10'},
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingImages();
  }

  Future<void> _loadExistingImages() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/get_arpl_practical_images.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'learner_id': widget.learnerID,
          'class_id': widget.classID,
          'ofo_number': widget.ofoNumber,
          'role': widget.role,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['images'] != null) {
          setState(() {
            for (var img in data['images']) {
              final taskId = img['practical_task_id'];
              if (!_practicalImages.containsKey(taskId)) {
                _practicalImages[taskId] = [];
              }
              _practicalImages[taskId]!.add({
                'id': img['id'],
                'path': img['image_path'],
                'caption': img['caption'] ?? '',
                'uploaded_at': img['uploaded_at'],
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[PRACTICAL_IMAGES] Error loading images: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _captureImage(String taskId) async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (photo != null) {
        await _showCaptionDialog(taskId, photo.path);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error capturing image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickFromGallery(String taskId) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (image != null) {
        await _showCaptionDialog(taskId, image.path);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showCaptionDialog(String taskId, String imagePath) async {
    final TextEditingController captionController = TextEditingController();

    await showDialog(
      if (!context.mounted) return;
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Caption'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.file(
              File(imagePath),
              height: 200,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: captionController,
              decoration: const InputDecoration(
                labelText: 'Caption (optional)',
                border: OutlineInputBorder(),
                hintText: 'Describe this image...',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _uploadImage(taskId, imagePath, captionController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6A1B9A),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadImage(
      String taskId, String imagePath, String caption) async {
    setState(() => _isSaving = true);

    try {
      // Read image as base64
      final bytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/save_arpl_practical_image.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'learner_id': widget.learnerID,
          'class_id': widget.classID,
          'ofo_number': widget.ofoNumber,
          'practical_task_id': taskId,
          'role': widget.role,
          'user_id': widget.userId,
          'image_base64': base64Image,
          'caption': caption,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            if (!_practicalImages.containsKey(taskId)) {
              _practicalImages[taskId] = [];
            }
            _practicalImages[taskId]!.add({
              'id': data['image_id'],
              'path': data['image_path'],
              'caption': caption,
              'uploaded_at': DateTime.now().toIso8601String(),
            });
          });

          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Image uploaded successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception(data['message'] ?? 'Upload failed');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteImage(String taskId, Map<String, dynamic> image) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Are you sure you want to delete this image?'),
        actions: [
          TextButton(
            if (!context.mounted) return;
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final response = await http.post(
          Uri.parse('${AppConfig.baseUrl}/delete_arpl_practical_image.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'image_id': image['id']}),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'success') {
            setState(() {
              _practicalImages[taskId]?.remove(image);
              if (_practicalImages[taskId]?.isEmpty == true) {
                _practicalImages.remove(taskId);
              }
            });

            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Image deleted'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF6A1B9A),
        title: Text(
            'ARPL Practical Evidence Images - ${widget.role.toUpperCase()}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _practicalTasks.length,
              itemBuilder: (context, index) {
                final task = _practicalTasks[index];
                final taskId = task['id']!;
                final taskName = task['name']!;
                final images = _practicalImages[taskId] ?? [];

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ExpansionTile(
                    leading: Icon(
                      images.isEmpty
                          ? Icons.image_not_supported
                          : Icons.photo_library,
                      color: images.isEmpty ? Colors.grey : Colors.green,
                    ),
                    title: Text(
                      taskName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${images.length} image(s)',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isSaving
                                        ? null
                                        : () => _captureImage(taskId),
                                    icon: const Icon(Icons.camera_alt),
                                    label: const Text('Take Photo'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6A1B9A),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isSaving
                                        ? null
                                        : () => _pickFromGallery(taskId),
                                    icon: const Icon(Icons.photo),
                                    label: const Text('From Gallery'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Image Grid
                            if (images.isNotEmpty)
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 1,
                                ),
                                itemCount: images.length,
                                itemBuilder: (context, imgIndex) {
                                  final image = images[imgIndex];
                                  return GestureDetector(
                                    onTap: () => _viewImageFullScreen(image),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.network(
                                            '${AppConfig.baseUrl}/serve_file.php?file=${Uri.encodeComponent(image['path'])}',
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stack) =>
                                                    Container(
                                              color: Colors.grey.shade300,
                                              child: const Icon(
                                                Icons.broken_image,
                                                size: 50,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: IconButton(
                                            onPressed: () =>
                                                _deleteImage(taskId, image),
                                            icon: const Icon(Icons.delete),
                                            style: IconButton.styleFrom(
                                              backgroundColor:
                                                  Colors.red.withValues(alpha: 0.8),
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ),
                                        if (image['caption']?.isNotEmpty ==
                                            true)
                                          Positioned(
                                            bottom: 0,
                                            left: 0,
                                            right: 0,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              color:
                                                  Colors.black.withValues(alpha: 0.7),
                                              child: Text(
                                                image['caption'],
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            if (images.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'No images captured yet',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _viewImageFullScreen(Map<String, dynamic> image) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Image Preview'),
              backgroundColor: const Color(0xFF6A1B9A),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                child: Image.network(
                  '${AppConfig.baseUrl}/serve_file.php?file=${Uri.encodeComponent(image['path'])}',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            if (image['caption']?.isNotEmpty == true)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.grey.shade200,
                child: Text(
                  image['caption'],
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
