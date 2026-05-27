import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:objectbox/objectbox.dart';
import 'services/gallery_service.dart';
import 'services/objectbox_service.dart';
import 'services/clip_service.dart';
import 'models/image_embedding.dart';
import 'objectbox.g.dart'; 

late ObjectBoxService objectBoxService;
final CLIPService clipService = CLIPService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  objectBoxService = await ObjectBoxService.create();
  // Initialize CLIP
  await clipService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Photo Search',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SearchPage(),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<ImageEmbedding> _searchResults = [];
  bool _isScanning = false;
  String _scanStatus = "";

  @override
  void initState() {
    super.initState();
    _loadAllFromDb();
  }

  void _loadAllFromDb() {
    setState(() {
      _searchResults = objectBoxService.imageBox.getAll();
    });
  }

  Future<void> _scanGallery() async {
    setState(() {
      _isScanning = true;
      _scanStatus = "Accessing Gallery...";
    });
    try {
      final galleryService = GalleryService();
      final images = await galleryService.getImagesForIndexing();

      final existingPaths = objectBoxService.imageBox
          .query()
          .build()
          .property(ImageEmbedding_.path)
          .find()
          .toSet();

      int processed = 0;
      int newlyAdded = 0;

      for (var imageData in images) {
        processed++;
        final String path = imageData['path'];
        final Uint8List bytes = imageData['bytes'];

        if (!existingPaths.contains(path)) {
          setState(() => _scanStatus = "Indexing $processed/${images.length}...");
          
          final embedding = await clipService.generateImageEmbeddingFromBytes(bytes);
          if (embedding.isNotEmpty) {
            objectBoxService.imageBox.put(ImageEmbedding(
              path: path,
              embedding: embedding,
            ));
            newlyAdded++;
            
            // Show images as they are added
            if (newlyAdded % 5 == 0) {
              _loadAllFromDb();
            }
          }
        }
      }
      
      _loadAllFromDb();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Finished! Processed ${images.length} images.')),
        );
      }
    } catch (e) {
      debugPrint('Error scanning gallery: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanStatus = "";
        });
      }
    }
  }

  Future<void> _search(String queryText) async {
    if (queryText.isEmpty) {
      _loadAllFromDb();
      return;
    }

    try {
      final embedding = await clipService.generateTextEmbedding(queryText);
      
      if (embedding.isEmpty) return;

      final queryEmbedding = Float32List.fromList(embedding);

      final query = objectBoxService.imageBox
          .query(ImageEmbedding_.embedding.nearestNeighborsF32(queryEmbedding, 20))
          .build();
      
      setState(() {
        _searchResults = query.find();
      });
      query.close();
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Photo Search'),
        actions: [
          if (_isScanning)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20, 
                height: 20, 
                child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor)
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _scanGallery,
              tooltip: 'Scan Gallery',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isScanning)
            Container(
              color: Colors.deepPurple.shade50,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                _scanStatus,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for "sunset", "dog", "beach"...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(_searchController.text),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _search,
            ),
          ),
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(child: Text('No images found.'))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final image = _searchResults[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(image.path),
                          fit: BoxFit.cover,
                          // Add error builder in case file path is invalid
                          errorBuilder: (context, error, stackTrace) => 
                            Container(color: Colors.grey, child: const Icon(Icons.error)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
