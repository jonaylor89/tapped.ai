import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intheloopapp/data/storage_repository.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/file_utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

final storageRef = FirebaseStorage.instance.ref();

class FirebaseStorageImpl extends StorageRepository {
  @override
  Future<String> uploadProfilePicture(
    String userId,
    File imageFile,
  ) async {
    final extension = p.extension(imageFile.path);
    final prefix = userId.isEmpty ? 'images/users' : 'images/users/$userId';

    final uniquePhotoId = const Uuid().v4();
    final image = await compressImage(uniquePhotoId, imageFile);

    final uploadTask = storageRef
        .child('$prefix/userProfile_$uniquePhotoId$extension')
        .putFile(image);
    final taskSnapshot = await uploadTask.whenComplete(() => null);
    final downloadUrl = await taskSnapshot.ref.getDownloadURL();

    return downloadUrl;
  }

  @override
  Future<File> compressImage(String photoId, File image) async {
    final tempDirection = await getTemporaryDirectory();
    final path = tempDirection.path;
    final extension = p.extension(image.path);

    logger.d('compressing image $path with extension: $extension');
    try {
      final compressedImage = await FlutterImageCompress.compressAndGetFile(
        image.absolute.path,
        '$path/img_$photoId$extension',
        quality: 70,
      );

      if (compressedImage == null) return image;

      return File(compressedImage.path);
    } catch (e) {
      logger.e('error compressing image: $e');
      return image;
    }
  }

  @override
  Future<String> uploadAudioAttachment(File audioFile) async {
    final extension = p.extension(audioFile.path);
    const prefix = 'audio/loops';

    final uniqueAudioId = const Uuid().v4();

    final uploadTask = storageRef
        .child('$prefix/loop_$uniqueAudioId$extension')
        .putFile(audioFile);

    final taskSnapshot = await uploadTask.whenComplete(() => null);
    final downloadUrl = await taskSnapshot.ref.getDownloadURL();

    return downloadUrl;
  }

  @override
  Future<String> uploadImageAttachment(File imageFile) async {
    final extension = p.extension(imageFile.path);
    const prefix = 'images/loops';
    final uniqueImageId = const Uuid().v4();

    final uploadTask = storageRef
        .child('$prefix/loop_$uniqueImageId$extension')
        .putFile(imageFile);

    final taskSnapshot = await uploadTask.whenComplete(() => null);
    final downloadUrl = await taskSnapshot.ref.getDownloadURL();

    return downloadUrl;
  }

  @override
  Future<String> uploadBadgeImage(String receiverId, File imageFile) async {
    final extension = p.extension(imageFile.path);
    final prefix =
        receiverId.isEmpty ? 'images/badges' : 'images/badges/$receiverId';

    final uniqueImageId = const Uuid().v4();

    final compressedImage = await compressImage(uniqueImageId, imageFile);
    final uploadTask = storageRef
        .child('$prefix/badge_$uniqueImageId$extension')
        .putFile(compressedImage);

    final taskSnapshot = await uploadTask.whenComplete(() => null);
    final downloadUrl = await taskSnapshot.ref.getDownloadURL();

    return downloadUrl;
  }

  @override
  Future<String> uploadAvatar({
    required String userId,
    required String originUrl,
  }) async {
    final extension = p.extension(originUrl);
    final prefix = userId.isEmpty ? 'images/avatars' : 'images/avatars/$userId';

    final uniqueImageId = const Uuid().v4();

    final File imageData = await DefaultCacheManager().getSingleFile(originUrl);

    final uploadTask = storageRef
        .child('$prefix/avatar_$uniqueImageId$extension')
        .putFile(imageData);

    final taskSnapshot = await uploadTask.whenComplete(() => null);
    final downloadUrl = await taskSnapshot.ref.getDownloadURL();

    return downloadUrl;
  }

  @override
  Future<String> uploadOpportunityFlier({
    required String opportunityId,
    required File imageFile,
  }) async {
    final ext = p.extension(imageFile.path);
    const prefix = 'images/opportunities';

    final uniqueImageId = const Uuid().v4();

    final compressedImage = await compressImage(uniqueImageId, imageFile);
    final uploadTask =
        storageRef.child('$prefix/$uniqueImageId$ext').putFile(compressedImage);

    final taskSnapshot = await uploadTask.whenComplete(() => null);
    final downloadUrl = await taskSnapshot.ref.getDownloadURL();

    return downloadUrl;
  }

  @override
  Future<String> uploadFeedbackScreenshot(
    String userId,
    Uint8List rawPng,
  ) async {
    const ext = '.png';
    final file = await writeToFile(rawPng);
    const prefix = 'images/feedback';

    final uniqueImageId = const Uuid().v4();

    final uploadTask =
        storageRef.child('$prefix/$uniqueImageId$ext').putFile(file);

    final taskSnapshot = await uploadTask.whenComplete(() => null);
    final downloadUrl = await taskSnapshot.ref.getDownloadURL();

    return downloadUrl;
  }

  @override
  Future<String> uploadPressKit({
    required String userId,
    required File pressKitFile,
  }) async {
    final extension = p.extension(pressKitFile.path);
    final prefix = userId.isEmpty ? 'press_kits' : 'press_kits/$userId';

    final uniquePressKitId = const Uuid().v4();

    final uploadTask = storageRef
        .child('$prefix/press_kit_$uniquePressKitId$extension')
        .putFile(pressKitFile);

    final taskSnapshot = await uploadTask.whenComplete(() => null);
    final downloadUrl = await taskSnapshot.ref.getDownloadURL();

    return downloadUrl;
  }

  @override
  Future<String> uploadBookingFlier({
    required String bookingId,
    required File imageFile,
  }) async {
    final ext = p.extension(imageFile.path);
    const prefix = 'images/bookings';

    final compressedImage = await compressImage(bookingId, imageFile);
    final uploadTask =
        storageRef.child('$prefix/$bookingId$ext').putFile(compressedImage);

    final taskSnapshot = await uploadTask.whenComplete(() => null);
    final downloadUrl = await taskSnapshot.ref.getDownloadURL();

    return downloadUrl;
  }
}
