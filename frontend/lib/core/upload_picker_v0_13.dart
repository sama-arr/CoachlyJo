import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'theme_v0_13.dart';
import 'i18n_v0_13.dart';

/// =============================================================================
/// Upload picker (v0.15 item 1).
///
/// v0.14 only offered the file browser, so a coach holding a paper certificate
/// had no way to upload it — they had to photograph it, find it in Files, and
/// pick it from there. This sheet offers all three sources everywhere an upload
/// happens: documents AND the profile photo.
///
///   Camera   — photograph a certificate or ID on the spot
///   Gallery  — a photo already taken
///   Files    — PDFs and Word documents
///
/// Returns a ready-to-send payload, so callers never juggle bytes or MIME
/// guessing themselves.
/// =============================================================================
class PickedUpload {
  final String fileName;
  final String mimeType;
  final String dataBase64;
  final int bytes;
  const PickedUpload({
    required this.fileName,
    required this.mimeType,
    required this.dataBase64,
    required this.bytes,
  });

  Map<String, dynamic> toJson({String? docType}) => {
        if (docType != null) 'docType': docType,
        'fileName': fileName,
        'mimeType': mimeType,
        'dataBase64': dataBase64,
      };
}

String mimeForName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.doc')) return 'application/msword';
  if (n.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  return 'image/jpeg';
}

/// Shows the source sheet and returns the chosen files.
///
/// [imagesOnly] drops the Files option (used for the profile photo, where a
/// PDF would be meaningless).
Future<List<PickedUpload>> pickUploads(
  BuildContext context, {
  bool imagesOnly = false,
  bool allowMultiple = true,
}) async {
  final c = AppColors.of(context);

  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(children: [
            const GradientIconBadge(icon: Icons.upload_file, size: 32),
            const SizedBox(width: 12),
            Text(tr(ctx, 'Choose a source'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: Text(tr(ctx, 'Take a photo')),
          subtitle: Text(tr(ctx, 'Use the camera now'),
              style: TextStyle(fontSize: 12, color: c.muted)),
          onTap: () => Navigator.pop(ctx, 'camera'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(tr(ctx, 'Choose from gallery')),
          subtitle: Text(tr(ctx, 'Pictures already on your phone'),
              style: TextStyle(fontSize: 12, color: c.muted)),
          onTap: () => Navigator.pop(ctx, 'gallery'),
        ),
        if (!imagesOnly)
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(tr(ctx, 'Choose a file')),
            subtitle: Text(tr(ctx, 'PDF or Word document'),
                style: TextStyle(fontSize: 12, color: c.muted)),
            onTap: () => Navigator.pop(ctx, 'files'),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (source == null) return [];

  try {
    if (source == 'camera' || source == 'gallery') {
      final picker = ImagePicker();
      if (source == 'camera' || !allowMultiple) {
        final shot = await picker.pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          // Keep uploads well inside the server's 10 MB limit while staying
          // legible enough to read a certificate.
          maxWidth: 2000,
          maxHeight: 2000,
          imageQuality: 85,
        );
        if (shot == null) return [];
        final bytes = await shot.readAsBytes();
        return [
          PickedUpload(
            fileName: shot.name,
            mimeType: mimeForName(shot.name),
            dataBase64: base64Encode(bytes),
            bytes: bytes.length,
          )
        ];
      }
      final shots = await picker.pickMultiImage(
          maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
      final out = <PickedUpload>[];
      for (final s in shots) {
        final bytes = await s.readAsBytes();
        out.add(PickedUpload(
          fileName: s.name,
          mimeType: mimeForName(s.name),
          dataBase64: base64Encode(bytes),
          bytes: bytes.length,
        ));
      }
      return out;
    }

    final res = await FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
    );
    if (res == null) return [];
    return res.files
        .where((f) => f.bytes != null)
        .map((f) => PickedUpload(
              fileName: f.name,
              mimeType: mimeForName(f.name),
              dataBase64: base64Encode(f.bytes!),
              bytes: f.bytes!.length,
            ))
        .toList();
  } catch (err) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'Could not read that file. Please try another one.')),
      ));
    }
    return [];
  }
}
