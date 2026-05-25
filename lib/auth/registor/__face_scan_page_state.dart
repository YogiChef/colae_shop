// ignore_for_file: use_build_context_synchronously, avoid_print

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceScanPage extends StatefulWidget {
  const FaceScanPage({super.key});
  @override
  State<FaceScanPage> createState() => _FaceScanPageState();
}

class _FaceScanPageState extends State<FaceScanPage> {
  bool _isScanning = false;
  bool _cameraInitialized = false;
  String _cameraStatus = 'กำลังเริ่มกล้อง...';
  CameraController? _cameraController;
  List<CameraDescription> cameras = [];
  late FaceDetector _faceDetector;
  late Future<void> _initializeCameraFuture;
  @override
  void initState() {
    super.initState();
    _initFaceDetector();
    _initializeCameraFuture = _initCamera();
  }

  void _initFaceDetector() {
    final options = FaceDetectorOptions(enableLandmarks: true);
    _faceDetector = FaceDetector(options: options);
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
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
      );
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _cameraInitialized = true;
          _cameraStatus = 'กล้องพร้อมสแกน - กดปุ่มเพื่อสแกน';
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

  Future<void> _scanFace() async {
    if (!_cameraInitialized ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      Fluttertoast.showToast(msg: 'กล้องไม่พร้อม ลองใหม่');
      await _initCamera();
      if (!_cameraInitialized) return;
    }
    if (!mounted) return;
    setState(() => _isScanning = true);
    try {
      final image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final faceImageBytes = await image.readAsBytes();
        print(
          'สแกนใบหน้าเต็มจอสำเร็จ - bytes: ${faceImageBytes.lengthInBytes}',
        );
        if (mounted) {
          setState(() {
            _cameraStatus = 'สแกนสำเร็จ - กำลังกลับ';
          });
        }
        Navigator.pop(context, faceImageBytes);
      } else {
        if (mounted) {
          setState(() {
            _cameraStatus = 'ไม่พบใบหน้า - ลองใหม่';
          });
        }
        Fluttertoast.showToast(msg: 'ไม่พบใบหน้า กรุณาลองใหม่');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraStatus = 'สแกนล้มเหลว: $e';
        });
        Fluttertoast.showToast(msg: 'สแกนใบหน้าล้มเหลว: $e');
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  void dispose() {
    try {
      _cameraController?.dispose();
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
    }
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สแกนใบหน้าเจ้าของร้าน'),
        backgroundColor: Colors.cyan.shade400,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
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
                        Icons.camera_alt,
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
              return CameraPreview(_cameraController!);
            },
          ),
          if (_isScanning)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _cameraStatus,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FloatingActionButton.extended(
                  onPressed: _isScanning ? null : _scanFace,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.camera_alt, color: Colors.white),
                  label: Text(_isScanning ? 'กำลังสแกน...' : 'สแกนใบหน้า'),
                  backgroundColor: Colors.cyan.shade400,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
