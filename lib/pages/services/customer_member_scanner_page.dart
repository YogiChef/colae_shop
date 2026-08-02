import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:colae_shop/services/sevice.dart';

class CustomerMemberScannerPage extends StatefulWidget {
  const CustomerMemberScannerPage({super.key});

  @override
  State<CustomerMemberScannerPage> createState() =>
      _CustomerMemberScannerPageState();
}

class _CustomerMemberScannerPageState extends State<CustomerMemberScannerPage>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.qrCode],
  );
  bool _scanned = false;
  late AnimationController _scanAnimController;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanAnimation = CurvedAnimation(
      parent: _scanAnimController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    if (!raw.startsWith('colae-buyer://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'QR นี้ไม่ใช่ QR สมาชิก Colae กรุณาให้ลูกค้าเปิดหน้า "QR สมาชิก"',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final buyerId = raw.replaceFirst('colae-buyer://', '').trim();
    if (buyerId.isEmpty) return;

    _scanned = true;
    _controller.stop();
    Navigator.pop(context, buyerId);
  }

  Widget _buildCorner({
    double? top,
    double? left,
    double? right,
    double? bottom,
    required bool showTop,
    required bool showBottom,
    required bool showLeft,
    required bool showRight,
  }) {
    const color = Colors.red;
    const thickness = 2.0;
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: SizedBox(
        width: 60.w,
        height: 60.w,
        child: CustomPaint(
          painter: _CornerPainter(
            color: color,
            thickness: thickness,
            radius: 5.r,
            showTop: showTop,
            showBottom: showBottom,
            showLeft: showLeft,
            showRight: showRight,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanAreaSize = MediaQuery.of(context).size.width * 0.7;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        title: Text(
          'สแกน QR Code',
          style: styles(
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          CustomPaint(
            size: Size.infinite,
            painter: _ScanOverlayPainter(scanAreaSize: scanAreaSize),
          ),

          Center(
            child: SizedBox(
              width: scanAreaSize,
              height: scanAreaSize,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  _buildCorner(
                    top: 0,
                    left: 0,
                    showTop: true,
                    showLeft: true,
                    showBottom: false,
                    showRight: false,
                  ),
                  _buildCorner(
                    top: 0,
                    right: 0,
                    showTop: true,
                    showRight: true,
                    showBottom: false,
                    showLeft: false,
                  ),
                  _buildCorner(
                    bottom: 0,
                    left: 0,
                    showBottom: true,
                    showLeft: true,
                    showTop: false,
                    showRight: false,
                  ),
                  // Bottom-right
                  _buildCorner(
                    bottom: 0,
                    right: 0,
                    showBottom: true,
                    showRight: true,
                    showTop: false,
                    showLeft: false,
                  ),

                  AnimatedBuilder(
                    animation: _scanAnimation,
                    builder: (_, __) {
                      final yOffset = _scanAnimation.value * (scanAreaSize - 3);
                      return Positioned(
                        top: yOffset,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.red.withValues(alpha: 0),
                                Colors.red.withValues(alpha: 0.9),
                                Colors.red,
                                Colors.red.withValues(alpha: 0.9),
                                Colors.red.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final double scanAreaSize;

  const _ScanOverlayPainter({required this.scanAreaSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);

    final cx = size.width / 2;
    final cy = size.height / 2;
    final half = scanAreaSize / 2;

    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()
      ..addRect(Rect.fromLTRB(cx - half, cy - half, cx + half, cy + half));

    final overlay = Path.combine(PathOperation.difference, outer, hole);
    canvas.drawPath(overlay, paint);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.scanAreaSize != scanAreaSize;
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final double radius;
  final bool showTop;
  final bool showBottom;
  final bool showLeft;
  final bool showRight;

  const _CornerPainter({
    required this.color,
    required this.thickness,
    required this.radius,
    required this.showTop,
    required this.showBottom,
    required this.showLeft,
    required this.showRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final t = thickness / 2;
    final r = radius;

    final path = Path();

    if (showTop && showLeft) {
      path.moveTo(w, t);
      path.lineTo(t + r, t);
      path.arcToPoint(
        Offset(t, t + r),
        radius: Radius.circular(r),
        clockwise: false,
      );
      path.lineTo(t, h);
    } else if (showTop && showRight) {
      path.moveTo(0, t);
      path.lineTo(w - t - r, t);
      path.arcToPoint(
        Offset(w - t, t + r),
        radius: Radius.circular(r),
        clockwise: true,
      );
      path.lineTo(w - t, h);
    } else if (showBottom && showLeft) {
      path.moveTo(t, 0);
      path.lineTo(t, h - t - r);
      path.arcToPoint(
        Offset(t + r, h - t),
        radius: Radius.circular(r),
        clockwise: false,
      );
      path.lineTo(w, h - t);
    } else if (showBottom && showRight) {
      path.moveTo(w - t, 0);
      path.lineTo(w - t, h - t - r);
      path.arcToPoint(
        Offset(w - t - r, h - t),
        radius: Radius.circular(r),
        clockwise: true,
      );
      path.lineTo(0, h - t);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.color != color ||
      old.thickness != thickness ||
      old.radius != radius ||
      old.showTop != showTop ||
      old.showBottom != showBottom ||
      old.showLeft != showLeft ||
      old.showRight != showRight;
}
