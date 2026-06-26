// ignore_for_file: avoid_print, use_build_context_synchronously

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/pages/main_vendor_page.dart';

class StoreLocationPage extends StatefulWidget {
  const StoreLocationPage({super.key});

  @override
  State<StoreLocationPage> createState() => _StoreLocationPageState();
}

class _StoreLocationPageState extends State<StoreLocationPage> {
  GoogleMapController? _mapController;
  LatLng _currentPosition = const LatLng(13.7563, 100.5018); // Default Bangkok
  final Set<Marker> _markers = {};
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  StreamSubscription<Position>? _positionStream;

  bool _userHasSelectedLocation = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _mapReady = false;
    _positionStream?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _safeAnimateCamera(CameraUpdate update) {
    if (_mapReady && mounted && _mapController != null) {
      _mapController!.animateCamera(update);
    }
  }

  void _startLocationStream() {
    _positionStream?.cancel();
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen(
          (Position position) {
            if (!_userHasSelectedLocation && mounted) {
              final newPos = LatLng(position.latitude, position.longitude);
              setState(() => _currentPosition = newPos);
              _updateMarker(newPos);
              _safeAnimateCamera(CameraUpdate.newLatLngZoom(newPos, 16.0));
            }
          },
          onError: (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('เกิดข้อผิดพลาดตำแหน่ง: $error')),
              );
            }
          },
          cancelOnError: false,
        );
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    final bool mapAlreadyReady = _mapController != null;

    if (!mapAlreadyReady) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('กรุณาเปิด Location Services ใน Settings');
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('กรุณาอนุญาต Location ใน Settings > App Permissions');
      }

      final position =
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          ).timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw Exception('หมดเวลา – ลองกดรีเฟรชอีกครั้ง'),
          );

      if (!mounted) return;

      final newPos = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = newPos;
        _isLoading = false;
      });

      _updateMarker(newPos);
      if (_mapReady) {
        _safeAnimateCamera(CameraUpdate.newLatLngZoom(newPos, 16.0));
      }

      _startLocationStream();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      _updateMarker(_currentPosition);
    }
  }

  void _updateMarker(LatLng position) {
    if (!mounted) return;
    setState(() {
      _markers
        ..clear()
        ..add(
          Marker(
            markerId: const MarkerId('store'),
            position: position,
            draggable: true,
            infoWindow: const InfoWindow(
              title: 'ร้านของคุณ',
              snippet: 'ลากเพื่อย้ายตำแหน่ง',
            ),
            onDragEnd: (LatLng newPos) {
              setState(() {
                _currentPosition = newPos;
                _userHasSelectedLocation = true;
              });
            },
          ),
        );
    });
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _currentPosition = position;
      _userHasSelectedLocation = true;
    });
    _updateMarker(position);
  }

  Future<void> _saveLocation() async {
    final user = auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อน')));
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      final location = GeoPoint(
        _currentPosition.latitude,
        _currentPosition.longitude,
      );
      await firestore.collection('vendors').doc(user.uid).set({
        'location': location,
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกตำแหน่งสำเร็จ!'),
          backgroundColor: Colors.green,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainVendorPage()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('บันทึกไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ปักหมุดร้านค้า'),
        backgroundColor: context.isDark ? Colors.transparent : mainColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'ตำแหน่งปัจจุบัน',
            onPressed: () async {
              setState(() {
                _userHasSelectedLocation = false;
                _error = null;
              });

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('กำลังดึงตำแหน่ง...'),
                  duration: Duration(seconds: 3),
                ),
              );

              try {
                LocationPermission permission =
                    await Geolocator.checkPermission();
                if (permission == LocationPermission.denied ||
                    permission == LocationPermission.deniedForever) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ไม่ได้รับอนุญาต Location')),
                  );
                  return;
                }

                final position =
                    await Geolocator.getCurrentPosition(
                      locationSettings: const LocationSettings(
                        accuracy: LocationAccuracy.high,
                        timeLimit: Duration(seconds: 10),
                      ),
                    ).timeout(
                      const Duration(seconds: 12),
                      onTimeout: () => throw Exception('หมดเวลา'),
                    );

                if (!mounted) return;
                final newPos = LatLng(position.latitude, position.longitude);
                setState(() => _currentPosition = newPos);
                _updateMarker(newPos);
                _safeAnimateCamera(CameraUpdate.newLatLngZoom(newPos, 16.0));

                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ──
          Positioned.fill(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _currentPosition,
                      zoom: 15.0,
                    ),
                    markers: _markers,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _mapReady = true;
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _safeAnimateCamera(
                          CameraUpdate.newLatLngZoom(_currentPosition, 16.0),
                        );
                      });
                    },
                    onTap: _onMapTap,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    mapType: MapType.normal,
                    zoomControlsEnabled: true,
                    rotateGesturesEnabled: true,
                    scrollGesturesEnabled: true,
                    zoomGesturesEnabled: true,
                    tiltGesturesEnabled: true,
                    liteModeEnabled: false,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  ),
          ),

          if (!_isLoading && _error == null)
            Positioned(
              top: 12.h,
              left: 16.w,
              right: 16.w,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app, color: Colors.blue, size: 20),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        'แตะแผนที่หรือลากหมุดเพื่อเลือกตำแหน่งร้าน',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_error != null)
            Positioned(
              top: 12.h,
              left: 16.w,
              right: 16.w,
              child: Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(_error!, style: TextStyle(fontSize: 12.sp)),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() => _error = null);
                        _getCurrentLocation();
                      },
                      icon: const Icon(Icons.refresh, color: Colors.orange),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),

      bottomNavigationBar: SafeArea(
        child: ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewPadding.bottom + 12.h,
              left: 20.w,
              right: 20.w,
              top: 8.h,
            ),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveLocation,
              icon: _isSaving
                  ? SizedBox(
                      width: 18.w,
                      height: 18.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_alt_rounded),
              label: Text(_isSaving ? 'กำลังบันทึก...' : 'บันทึกตำแหน่ง'),
              style: ElevatedButton.styleFrom(
                backgroundColor: mainColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.green.shade300,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
                textStyle: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
