// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:thai_id_card_numbers/thai_id_card_numbers.dart';
import 'package:colae_shop/services/sevice.dart';

class IdScanPage extends StatefulWidget {
  const IdScanPage({super.key});
  @override
  State<IdScanPage> createState() => _IdScanPageState();
}

class _IdScanPageState extends State<IdScanPage> {
  bool _isScanning = false;
  bool _cameraInitialized = false;
  bool _showPreview = false;
  String _cameraStatus = 'กำลังเริ่มกล้อง...';
  String _parsedIdNumber = '';
  String _parsedBirthDate = '';
  String _parsedCardOwnerName = '';
  XFile? _scannedImage;
  CameraController? _cameraController;
  List<CameraDescription> cameras = [];
  late TextRecognizer _textRecognizer;
  late Future<void> _initializeCameraFuture;
  @override
  void initState() {
    super.initState();
    _initTextRecognizer();
    _initializeCameraFuture = _initCamera();
  }

  void _initTextRecognizer() {
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  Future<void> _initCamera() async {
    try {
      if (!mounted) return;
      cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraStatus = 'ไม่พบกล้อง';
          });
          Fluttertoast.showToast(msg: 'ไม่พบกล้อง');
        }
        return;
      }
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.veryHigh,
      );
      await _cameraController!.initialize();
      await _cameraController!.setFocusMode(FocusMode.auto);
      await _cameraController!.setExposureMode(ExposureMode.auto);
      if (mounted) {
        setState(() {
          _cameraInitialized = true;
          _cameraStatus = 'วางบัตรในกรอบด้านล่าง';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraStatus = 'กล้องล้มเหลว: $e';
        });
        Fluttertoast.showToast(msg: 'ไม่สามารถเปิดกล้องได้: $e');
      }
    }
  }

  void _parseIdCardData(String recognizedText) {
    try {
      _parsedIdNumber = '';
      _parsedBirthDate = '';
      _parsedCardOwnerName = '';
      if (recognizedText.isEmpty) {
        _showPreview = false;
        setState(() {
          _cameraStatus = 'OCR ไม่พบข้อความ ลองสแกนใหม่';
        });
        Fluttertoast.showToast(msg: 'OCR ไม่พบข้อความ ลองสแกนชัดๆ ในที่สว่าง');
        return;
      }
      String text = recognizedText.replaceAll(RegExp(r'\s+'), ' ');

      final cleanText = recognizedText.replaceAll(RegExp(r'[^\d\s]'), ' ');
      RegExp idRegex = RegExp(r'\d[\d\s\-]{11,15}\d');
      Match? idMatch = idRegex.firstMatch(cleanText);
      if (idMatch != null) {
        final rawId = idMatch.group(0)!.replaceAll(RegExp(r'[^\d]'), '');
        if (rawId.length == 13) {
          final thaiIdValidator = ThaiIdCardNumbers();
          if (thaiIdValidator.validate(rawId)) {
            _parsedIdNumber = rawId;
          }
        }
      }

      String firstName = '';
      RegExp firstRegex = RegExp(
        r'(?:Name|Neme|Nane)[\s:]*Mr\.\s*([A-Za-z\u0E00-\u0E7F]+?)(?=\s*(?:Last|นามสกุล|เลขบัตร|\d|$))',
      );
      Match? firstMatch = firstRegex.firstMatch(text);
      if (firstMatch != null) {
        firstName = firstMatch.group(1)!.trim();
      }

      String lastName = '';
      RegExp lastRegex = RegExp(
        r'Last\s*[Nn][a-z]{2,5}[\s:]*([A-Za-z\u0E00-\u0E7F]{2,})',
        caseSensitive: false,
      );
      Match? lastMatch = lastRegex.firstMatch(text);
      if (lastMatch != null) {
        lastName = lastMatch.group(1)!.trim();
      }

     
      _parsedCardOwnerName = firstName.isNotEmpty ? firstName : '';
      if (lastName.isNotEmpty) {
        _parsedCardOwnerName +=
            (_parsedCardOwnerName.isNotEmpty ? ' ' : '') + lastName;
      }

      RegExp birthRegex = RegExp(
        r'(?:Date\s*of\s*B[a-z]{2,5}|D[ae]t[ae]\s*of\s*B[a-z]{2,5})[\s:]*'
        r'(\d{1,2})[\s./]*'
        r'([A-Za-z]{3,9})[,.\s]*'
        r'(\d{4})',
        caseSensitive: false,
      );
      Match? birthMatch = birthRegex.firstMatch(text);
      if (birthMatch != null) {
        String day = birthMatch.group(1)!;
        String month = birthMatch
            .group(2)!
            .replaceAll(RegExp(r'[,.]'), '')
            .trim();
        String year = birthMatch.group(3)!;
        if (year.length == 4 &&
            int.tryParse(year) != null &&
            int.parse(year) > 2500) {
          year = (int.parse(year) - 543).toString();
        }
        _parsedBirthDate = '$day/$month/$year';
      }

      if (mounted) {
        setState(() {
          _showPreview = true;
        });
        bool isComplete =
            _parsedIdNumber.isNotEmpty &&
            _parsedCardOwnerName.isNotEmpty &&
            _parsedBirthDate.isNotEmpty;
        String successMsg = 'สแกนสำเร็จ! ';
        if (_parsedIdNumber.isNotEmpty) {
          successMsg += 'เลขบัตร: $_parsedIdNumber ';
        }
        if (_parsedCardOwnerName.isNotEmpty) {
          successMsg += 'ชื่อ: $_parsedCardOwnerName ';
        }
        if (_parsedBirthDate.isNotEmpty) {
          successMsg += 'วันเกิด: $_parsedBirthDate';
        }
        if (isComplete) {
          Fluttertoast.showToast(msg: '$successMsg (ครบถ้วน!)');
        } else {
          Fluttertoast.showToast(msg: '$successMsg (ไม่ครบ สแกนใหม่)');
        }
      }
    } catch (e) {
      setState(() {
        _showPreview = false;
        _cameraStatus = 'Parse ล้มเหลว ลองสแกนใหม่';
      });
      Fluttertoast.showToast(msg: 'Parse ข้อมูลล้มเหลว ลองสแกนใหม่');
    }
  }

  Future<void> _scanIdCard() async {
    if (!_cameraInitialized || _cameraController == null) return;
    if (!mounted) return;
    setState(() => _isScanning = true);

    try {
      String bestText = '';
      int bestScore = 0;
      XFile? bestImage;

      for (int attempt = 0; attempt < 3; attempt++) {
        await Future.delayed(const Duration(milliseconds: 300));
        final image = await _cameraController!.takePicture();
        final inputImage = InputImage.fromFilePath(image.path);
        final recognized = await _textRecognizer.processImage(inputImage);
        final text = recognized.text;

        int score = 0;
        if (RegExp(r'\d{13}').hasMatch(text.replaceAll(' ', ''))) score++;
        if (text.contains('Name') ||
            text.contains('Neme') ||
            text.contains('Nane')) {
          score++;
        }
        if (text.contains('Birth') ||
            text.contains('Brth') ||
            text.contains('Bith')) {
          score++;
        }

        if (score > bestScore) {
          bestScore = score;
          bestText = text;
          bestImage = image;
        }

        if (score >= 3) break;
      }

      _scannedImage = bestImage;
      _parseIdCardData(bestText);
    } catch (e) {
      if (mounted) {
        setState(() => _cameraStatus = 'สแกนล้มเหลว ลองใหม่');
        Fluttertoast.showToast(msg: 'สแกนล้มเหลว: $e');
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _rescan() {
    setState(() {
      _showPreview = false;
      _parsedIdNumber = '';
      _parsedBirthDate = '';
      _parsedCardOwnerName = '';
      _scannedImage = null;
      _cameraStatus = 'วางบัตรในกรอบด้านล่าง';
    });
  }

  void _confirmScan() {
    bool isComplete =
        _parsedIdNumber.isNotEmpty &&
        _parsedCardOwnerName.isNotEmpty &&
        _parsedBirthDate.isNotEmpty;
    if (_scannedImage != null && isComplete) {
      Navigator.pop(context, {
        'path': _scannedImage!.path,
        'idNumber': _parsedIdNumber,
        'birthDate': _parsedBirthDate,
        'cardOwnerName': _parsedCardOwnerName,
      });
    } else {
      Fluttertoast.showToast(
        msg: 'ข้อมูลไม่ครบ (ID/ชื่อ/วันเกิด) กรุณาสแกนใหม่',
      );
    }
  }

  @override
  void dispose() {
    try {
      _cameraController?.dispose();
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
    }
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สแกนบัตรประชาชน'),
        backgroundColor: Colors.cyan.shade400,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          if (!_showPreview) ...[
            FutureBuilder<void>(
              future: _initializeCameraFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError ||
                    !_cameraInitialized ||
                    _cameraController == null ||
                    !_cameraController!.value.isInitialized) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.credit_card,
                          size: 100,
                          color: Colors.grey,
                        ),
                        Text(
                          _cameraStatus,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        ElevatedButton(
                          onPressed: _initCamera,
                          child: const Text('ลองเริ่มกล้องใหม่'),
                        ),
                      ],
                    ),
                  );
                }
                return Stack(
                  children: [
                    CameraPreview(_cameraController!),
                    Positioned(
                      top: height * 0.2, 
                      left: 12.w,
                      right: 12.w,
                      child: Container(
                        height: 240.h, 
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.green.shade400,
                            width: 3,
                            style: BorderStyle.solid,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Center(
                            child: Text(
                              'วางบัตรที่นี่ (ต่ำลง)',
                              style: TextStyle(
                                color: Colors.green.shade400,
                                fontSize: 14.sp,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_isScanning)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ] else ...[
            // Preview mode หลัง scan
            Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(_scannedImage!.path),
                        fit: BoxFit.contain,
                      ),
                      Positioned(
                        bottom: 120.h,
                        left: 12.w,
                        right: 12.w,
                        child: Container(
                          padding: EdgeInsets.all(16.w),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ข้อมูลที่สแกนได้:',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8.h),
                              Text(
                                'เลขบัตร: ${_parsedIdNumber.isEmpty ? 'ไม่พบ' : _parsedIdNumber}',
                                style: const TextStyle(color: Colors.white),
                              ),
                              Text(
                                'ชื่อ: ${_parsedCardOwnerName.isEmpty ? 'ไม่พบ' : _parsedCardOwnerName}',
                                style: const TextStyle(color: Colors.white),
                              ),
                              Text(
                                'วันเกิด: ${_parsedBirthDate.isEmpty ? 'ไม่พบ' : _parsedBirthDate}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          // Bottom buttons
          
          Positioned(
            top: height * 0.15,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                _cameraStatus,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  shadows: [
                    Shadow(
                      offset: Offset(1, 1),
                      blurRadius: 2,
                      color: Colors.black,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: MediaQuery.of(context).viewPadding.bottom * 0.02),
          child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _showPreview
                      ? ElevatedButton.icon(
                          onPressed: _rescan,
                          icon: const Icon(Icons.refresh),
                          label: const Text('สแกนใหม่'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                        )
                      : FloatingActionButton.extended(
                          onPressed: _isScanning || _showPreview
                              ? null
                              : _scanIdCard,
                          icon: _isScanning
                              ? SizedBox(
                                  width: 20.w,
                                  height: 20.h,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.camera_alt, color: Colors.white),
                          label: Text(_isScanning ? 'กำลังสแกน...' : 'สแกนบัตร'),
                          backgroundColor: Colors.cyan.shade400,
                        ),
                  _showPreview
                      ? ElevatedButton.icon(
                          onPressed: _confirmScan,
                          icon: const Icon(Icons.check),
                          label: const Text('ยืนยัน'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                        )
                      : const SizedBox.shrink(),
                ],
              ),
        ),
      ),
    );
  }
}
