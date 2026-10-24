import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../data/repository.dart';
import '../domain/bill_rules.dart';

class ScannedBill {
  final BillDraft draft;
  final Map<String, dynamic> attachment;
  ScannedBill(this.draft, this.attachment);
}

class BillScanner {
  final Repository repo;
  final picker = ImagePicker();
  BillScanner(this.repo);
  Future<ScannedBill?> capture(ImageSource source) async {
    final image = await picker.pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 3200,
      imageQuality: 90,
    );
    if (image == null) return null;
    return readImage(image.path);
  }

  Future<ScannedBill?> recover() async {
    final lost = await picker.retrieveLostData();
    if (lost.exception != null) throw lost.exception!;
    final files = lost.files;
    if (files == null || files.isEmpty) return null;
    return readImage(files.first.path);
  }

  Future<ScannedBill> readImage(String path) async {
    final attachment = await repo.importAttachment(path);
    final name = attachment['file'] as String;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(repo.file(name).path),
      );
      attachment['text'] = result.text;
      return ScannedBill(parseBill(result.text, DateTime.now()), attachment);
    } catch (_) {
      await repo.removeAttachment(name);
      rethrow;
    } finally {
      await recognizer.close();
    }
  }
}
