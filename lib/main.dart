import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Get available cameras
  final cameras = await availableCameras();
  
  runApp(HouseInspectorApp(cameras: cameras));
}

class HouseInspectorApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const HouseInspectorApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'House Inspector',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: MainScreen(cameras: cameras),
    );
  }
}

class InspectionItem {
  final String room;
  final String? imagePath;
  final Uint8List? imageData;
  final String comment;
  final DateTime timestamp;

  InspectionItem({
    required this.room,
    this.imagePath,
    this.imageData,
    required this.comment,
    required this.timestamp,
  });
}

class MainScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MainScreen({super.key, required this.cameras});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final List<InspectionItem> _inspectionItems = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _addInspectionItem(InspectionItem item) {
    setState(() {
      _inspectionItems.add(item);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('House Inspector'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.camera_alt), text: 'Inspect'),
            Tab(icon: Icon(Icons.assessment), text: 'Report'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          InspectionScreen(
            cameras: widget.cameras,
            onItemAdded: _addInspectionItem,
          ),
          ReportScreen(inspectionItems: _inspectionItems),
        ],
      ),
    );
  }
}

class InspectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Function(InspectionItem) onItemAdded;

  const InspectionScreen({
    super.key,
    required this.cameras,
    required this.onItemAdded,
  });

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  CameraController? _cameraController;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _selectedRoom = 'Kitchen';
  String _currentComment = '';
  Uint8List? _capturedImage;
  bool _speechAvailable = false;

  final List<String> _rooms = [
    'Kitchen',
    'Living Room',
    'Bathroom',
    'Bedroom',
    'Dining Room',
    'Garage',
    'Basement',
    'Attic',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeSpeech();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isNotEmpty) {
      _cameraController = CameraController(
        widget.cameras[0],
        ResolutionPreset.high,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    }
  }

  Future<void> _initializeSpeech() async {
    _speech = stt.SpeechToText();
    _speechAvailable = await _speech.initialize(
      onStatus: (status) => setState(() => _isListening = status == 'listening'),
      onError: (error) => print('Error: $error'),
    );
    setState(() {});
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final XFile image = await _cameraController!.takePicture();
      final Uint8List imageData = await image.readAsBytes();
      setState(() {
        _capturedImage = imageData;
      });
    } catch (e) {
      print('Error taking picture: $e');
    }
  }

  Future<void> _startListening() async {
    if (_speechAvailable && !_isListening) {
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _currentComment = result.recognizedWords;
          });
        },
      );
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  void _addToReport() {
    if (_capturedImage != null || _currentComment.isNotEmpty) {
      final item = InspectionItem(
        room: _selectedRoom,
        imageData: _capturedImage,
        comment: _currentComment,
        timestamp: DateTime.now(),
      );
      
      widget.onItemAdded(item);
      
      // Reset form
      setState(() {
        _capturedImage = null;
        _currentComment = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added to $_selectedRoom report'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Room Selector
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Room:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRoom,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _rooms.map((room) => DropdownMenuItem(
                      value: room,
                      child: Text(room),
                    )).toList(),
                    onChanged: (value) => setState(() => _selectedRoom = value!),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Camera Preview
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text('Camera', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _capturedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(_capturedImage!, fit: BoxFit.cover),
                          )
                        : _cameraController != null && _cameraController!.value.isInitialized
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CameraPreview(_cameraController!),
                              )
                            : const Center(child: Text('Camera not available')),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _takePicture,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_capturedImage != null ? 'Retake Photo' : 'Take Photo'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Speech to Text
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Type or dictate your comments...',
                    ),
                    onChanged: (value) => setState(() => _currentComment = value),
                    controller: TextEditingController(text: _currentComment),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _speechAvailable
                            ? (_isListening ? _stopListening : _startListening)
                            : null,
                        icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                        label: Text(_isListening ? 'Stop' : 'Dictate'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isListening ? Colors.red : null,
                        ),
                      ),
                      if (!_speechAvailable) ...[
                        const SizedBox(width: 8),
                        const Text('Speech not available', style: TextStyle(color: Colors.grey)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Add to Report Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_capturedImage != null || _currentComment.isNotEmpty) ? _addToReport : null,
              icon: const Icon(Icons.add),
              label: const Text('Add to Report'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReportScreen extends StatelessWidget {
  final List<InspectionItem> inspectionItems;

  const ReportScreen({super.key, required this.inspectionItems});

  @override
  Widget build(BuildContext context) {
    if (inspectionItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No inspection items yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
            Text('Go to the Inspect tab to start adding items'),
          ],
        ),
      );
    }

    // Group items by room
    final Map<String, List<InspectionItem>> groupedItems = {};
    for (final item in inspectionItems) {
      groupedItems.putIfAbsent(item.room, () => []).add(item);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedItems.keys.length,
      itemBuilder: (context, index) {
        final room = groupedItems.keys.elementAt(index);
        final items = groupedItems[room]!;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.imageData != null) ...[
                        const Text('Photo:', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            item.imageData!,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (item.comment.isNotEmpty) ...[
                        const Text('Comments:', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(item.comment),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        'Added: ${item.timestamp.toString().substring(0, 19)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (items.indexOf(item) < items.length - 1)
                        const Divider(height: 32),
                    ],
                  ),
                )),
              ],
            ),
          ),
        );
      },
    );
  }
}