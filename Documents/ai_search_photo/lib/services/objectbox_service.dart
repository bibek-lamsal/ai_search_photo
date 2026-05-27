import 'package:ai_search_photo/models/image_embedding.dart';
import 'package:ai_search_photo/objectbox.g.dart'; // This will be generated
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ObjectBoxService {
  late final Store store;
  late final Box<ImageEmbedding> imageBox;

  ObjectBoxService._create(this.store) {
    imageBox = Box<ImageEmbedding>(store);
  }

  static Future<ObjectBoxService> create() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final store = await openStore(directory: p.join(docsDir.path, "obx-images"));
    return ObjectBoxService._create(store);
  }
}
