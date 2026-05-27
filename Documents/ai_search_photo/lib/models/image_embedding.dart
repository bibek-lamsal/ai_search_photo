import 'package:objectbox/objectbox.dart';

@Entity()
class ImageEmbedding {
  @Id()
  int id = 0;

  String path;

  @HnswIndex(dimensions: 512)
  @Property(type: PropertyType.floatVector)
  List<double> embedding;

  ImageEmbedding({
    this.id = 0,
    required this.path,
    required this.embedding,
  });
}
