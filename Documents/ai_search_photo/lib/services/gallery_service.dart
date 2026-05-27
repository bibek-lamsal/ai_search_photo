import 'dart:io';
import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';

class GalleryService {
  Future<List<Map<String, dynamic>>> getImagesForIndexing() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      return [];
    }

    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );

    if (paths.isEmpty) {
      return [];
    }

    // Get all photos from the "Recent" or first album
    final List<AssetEntity> entities = await paths[0].getAssetListPaged(
      page: 0,
      size: 1000,
    );

    List<Map<String, dynamic>> results = [];
    for (var entity in entities) {
      // Get high-quality thumbnail (224 is perfect for CLIP input size)
      final Uint8List? thumbnail = await entity.thumbnailDataWithSize(
        const ThumbnailSize(224, 224),
        quality: 100,
      );
      final File? file = await entity.file;
      
      if (thumbnail != null && file != null) {
        results.add({
          'path': file.path,
          'bytes': thumbnail,
        });
      }
    }

    return results;
  }

  // Keep the old method for backward compatibility if needed, or remove it
  Future<List<File>> getImages() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) return [];
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(type: RequestType.image);
    if (paths.isEmpty) return [];
    final List<AssetEntity> entities = await paths[0].getAssetListPaged(page: 0, size: 1000);
    List<File> imageFiles = [];
    for (var entity in entities) {
      final file = await entity.file;
      if (file != null) imageFiles.add(file);
    }
    return imageFiles;
  }
}
