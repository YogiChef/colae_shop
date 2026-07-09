// ignore_for_file: use_build_context_synchronously, avoid_print, unused_field
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:thai_address_picker/thai_address_picker.dart';
import 'package:colae_shop/auth/registor/__face_scan_page_state.dart';
import 'package:colae_shop/auth/registor/__id_scan_page_state.dart';
import 'package:colae_shop/auth/registor/vendor_registor_page.dart';
import 'package:colae_shop/auth/vendor_auth.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/widgets/button_widget.dart';
import 'package:colae_shop/widgets/input_textfield.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

class VendorProfileEditPage extends StatefulWidget {
  const VendorProfileEditPage({super.key});
  @override
  State<VendorProfileEditPage> createState() => _VendorProfileEditPageState();
}

class _VendorProfileEditPageState extends State<VendorProfileEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  ThaiAddress? _selectedAddress;
  Province? _initialProvince;
  District? _initialDistrict;
  SubDistrict? _initialSubDistrict;
  bool _addressLoaded = false;
  String name = '';
  String ownerName = '';
  String email = '';
  String phone = '';
  String taxNumber = '';
  String addres = '';
  String zipcode = '';
  String country = 'Thailand';
  String subdistrict = '';
  String district = '';
  String province = '';
  String vzipcode = '';
  String category = '';
  String bankName = '';
  String bankAccount = '';
  String promptPayId = '';
  String idNumber = '';
  String birthDate = '';
  String cardOwnerName = '';
  Uint8List? image;
  Uint8List? faceImage;
  Uint8List? idCardImage;
  Uint8List? qrImage;
  String? currentImageUrl;
  String? currentFaceImageUrl;
  String? currentIdCardImageUrl;
  String? currentQrImageUrl;
  final List<String> _taxOptions = ['YES', 'NO'];
  String? _taxStatus;
  final List<String> _bankList = [
    'ธนาคารกสิกรไทย (Kasikorn Bank)',
    'ธนาคารกรุงไทย (Krungthai Bank)',
    'ธนาคารไทยพาณิชย์ (SCB)',
    'ธนาคารกรุงศรีอยุธยา (Krungsri)',
    'ธนาคารทหารไทยธนชาต (TMBThanachart)',
    'ธนาคารกรุงเทพ (Bangkok Bank)',
    'ธนาคารออมสิน (Government Savings Bank)',
    'ธนาคารอาคารสงเคราะห์ (Government Housing Bank)',
  ];
  String? _bankDropdownValue;
  List<String> _categoryList = [];
  final _storeNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _bankAccountController = TextEditingController();
  final _promptPayIdController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _cardOwnerNameController = TextEditingController();
  bool _isLoading = true;

  Future<String> uploadImagToStorage(
    Uint8List imageBytes, {
    required String type,
  }) async {
    const int maxRetries = 1;
    for (int retry = 0; retry <= maxRetries; retry++) {
      try {
        if (_auth.currentUser == null) {
          return '';
        }
        if (imageBytes.isEmpty) {
          return '';
        }
        String uid = _auth.currentUser!.uid;
        String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        String fileName = '${uid}_${type}_$timestamp.jpg';
        Reference ref = FirebaseStorage.instance.ref().child(
          'images/$fileName',
        );
        print(
          'Attempt ${retry + 1}: Uploading $type to path: ${ref.fullPath} (size: ${imageBytes.lengthInBytes} bytes)',
        );
        UploadTask uploadTask = ref.putData(imageBytes);
        TaskSnapshot snapshot = await uploadTask.whenComplete(() {});
        if (snapshot.state == TaskState.success) {
          try {
            String downloadUrl = await snapshot.ref.getDownloadURL();

            return downloadUrl;
          } catch (urlError) {
            await ref.delete().catchError((e) => print('Cleanup error: $e'));
            if (retry < maxRetries) continue;
            return '';
          }
        } else {
          if (retry < maxRetries) continue;
          return '';
        }
      } on FirebaseException catch (e) {
        print(
          'Firebase Storage error for $type (attempt ${retry + 1}): ${e.code} - ${e.message}',
        );
        if (e.code == 'object-not-found' && retry < maxRetries) continue;
        return '';
      } catch (e) {
        if (retry < maxRetries) continue;
        return '';
      }
    }
    return '';
  }

  Future<void> updateVendorData(Map<String, dynamic> vendorData) async {
    try {
      String uid = _auth.currentUser!.uid;
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      await FirebaseFirestore.instance.collection('vendors').doc(uid).update({
        ...vendorData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _loadVendorData() async {
    try {
      if (_auth.currentUser == null) {
        Get.to(() => const VendorAuthPage());
        return;
      }
      String uid = _auth.currentUser!.uid;
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('vendors')
          .doc(uid)
          .get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            name = data['bussinessName'] ?? '';
            ownerName = data['ownerName'] ?? '';
            email = data['email'] ?? '';
            phone = data['phone'] ?? '';
            taxNumber = data['taxNo'] == 'null' ? '' : data['taxNo'] ?? '';
            addres = data['address'] ?? '';
            zipcode = data['vzipcode'] ?? '';
            country = data['country'] ?? 'Thailand';
            district = data['district'] ?? '';
            province = data['province'] ?? '';
            subdistrict = data['subdistrict'] ?? '';
            category = data['category'] ?? '';
            bankName = data['bankName'] ?? '';
            bankAccount = data['bankAccount'] == 'null'
                ? ''
                : data['bankAccount'] ?? '';
            promptPayId = data['promptPayId'] == 'null'
                ? ''
                : data['promptPayId'] ?? '';
            _taxStatus = data['taxStatus'] ?? 'NO';
            idNumber = data['idNumber'] ?? '';
            birthDate = data['birthDate'] ?? '';
            cardOwnerName = data['cardOwnerName'] ?? '';
            currentImageUrl = data['image'];
            currentFaceImageUrl = data['faceImage'];
            currentIdCardImageUrl = data['idCardImage'];
            currentQrImageUrl = data['qrCodeImage'];
            _storeNameController.text = name;
            _ownerNameController.text = ownerName;
            _emailController.text = email;
            _phoneController.text = phone;
            _addressController.text = addres;
            _taxNumberController.text = taxNumber;
            _bankAccountController.text = bankAccount;
            _promptPayIdController.text = promptPayId;
            _idNumberController.text = idNumber;
            _birthDateController.text = birthDate;
            _cardOwnerNameController.text = cardOwnerName;
            _categoryDropdownValue = category;
            _bankDropdownValue = bankName;
          });
        }
      } else {
        Fluttertoast.showToast(msg: 'ไม่พบข้อมูลโปรไฟล์ กรุณาลงทะเบียนใหม่');
        Get.to(() => const VendorRegistorPage());
      }
      // โหลด Province/District/SubDistrict objects จาก repository
      try {
        final repo = ThaiAddressRepository();
        await repo.initialize();

        if (province.isNotEmpty) {
          _initialProvince = repo.provinces.firstWhereOrNull(
            (p) => p.nameTh == province,
          );
          if (_initialProvince != null && district.isNotEmpty) {
            _initialDistrict = repo.districts.firstWhereOrNull(
              (x) =>
                  x.nameTh == district && x.provinceId == _initialProvince!.id,
            );
            if (_initialDistrict != null && subdistrict.isNotEmpty) {
              _initialSubDistrict = repo.subDistricts.firstWhereOrNull(
                (x) =>
                    x.nameTh == subdistrict &&
                    x.districtId == _initialDistrict!.id,
              );
            }
          }
        }
      } catch (e) {
        print('Error loading address objects: $e');
      }
      if (mounted) {
        setState(() {
          _addressLoaded = true;
        });
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'เกิดข้อผิดพลาดในการโหลดข้อมูล: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> save() async {
    if (_formKey.currentState!.validate()) {
      name = _storeNameController.text.trim();
      ownerName = _ownerNameController.text.trim();
      email = _emailController.text.trim();
      phone = _phoneController.text.trim();
      addres = _addressController.text.trim();
      taxNumber = _taxNumberController.text.trim();
      category = _categoryDropdownValue ?? '';
      bankName = _bankDropdownValue ?? '';
      bankAccount = _bankAccountController.text.trim();
      promptPayId = _promptPayIdController.text.trim();
      if (name.isEmpty) {
        Fluttertoast.showToast(msg: 'กรุณากรอกชื่อร้าน');
        return;
      }
      if (ownerName.isEmpty) {
        Fluttertoast.showToast(msg: 'กรุณากรอกชื่อเจ้าของร้าน');
        return;
      }
      if (email.isEmpty) {
        Fluttertoast.showToast(msg: 'Email cannot be empty');
        return;
      }
      if (bankName.isNotEmpty &&
          bankAccount.isEmpty &&
          promptPayId.isEmpty &&
          (qrImage == null && currentQrImageUrl == null)) {
        Fluttertoast.showToast(
          msg: 'กรุณากรอกเลขบัญชี, PromptPay ID หรืออัปโหลด QR Code',
        );
        return;
      }
      if (idNumber.isEmpty &&
          idCardImage == null &&
          currentIdCardImageUrl == null) {
        Fluttertoast.showToast(msg: 'กรุณาสแกนบัตรประชาชนเพื่อยืนยันตัวตน');
        return;
      }
      EasyLoading.show(status: 'กำลังอัปเดต...');
      try {
        await _auth.currentUser!.reload();
        String imageUrl = currentImageUrl ?? '';
        if (image != null && image!.isNotEmpty) {
          imageUrl = await uploadImagToStorage(image!, type: 'store');
          if (imageUrl.isEmpty) {}
        }
        String faceImageUrl = currentFaceImageUrl ?? '';
        if (faceImage != null && faceImage!.isNotEmpty) {
          faceImageUrl = await uploadImagToStorage(faceImage!, type: 'face');
          if (faceImageUrl.isEmpty) {}
        }
        String idCardImageUrl = currentIdCardImageUrl ?? '';
        if (idCardImage != null && idCardImage!.isNotEmpty) {
          idCardImageUrl = await uploadImagToStorage(
            idCardImage!,
            type: 'idcard',
          );
          if (idCardImageUrl.isEmpty) {}
        }
        String qrImageUrl = currentQrImageUrl ?? '';
        if (qrImage != null && qrImage!.isNotEmpty) {
          qrImageUrl = await uploadImagToStorage(qrImage!, type: 'qr');
          if (qrImageUrl.isEmpty) {}
        }
        String warningMsg = '';
        if (imageUrl.isEmpty && image != null) warningMsg += 'รูปหน้าร้าน, ';
        if (faceImageUrl.isEmpty && faceImage != null) {
          warningMsg += 'รูปใบหน้า, ';
        }
        if (idCardImageUrl.isEmpty && idCardImage != null) {
          warningMsg += 'รูปบัตรประชาชน, ';
        }
        if (qrImageUrl.isEmpty && qrImage != null) warningMsg += 'QR Code, ';
        if (warningMsg.isNotEmpty) {
          warningMsg = warningMsg.substring(0, warningMsg.length - 2);
          warningMsg += ' อัปโหลดไม่สำเร็จ';
        }
        Map<String, dynamic> vendorData = {
          'category': category,
          'bussinessName': name,
          'ownerName': ownerName,
          'email': email,
          'phone': phone,
          'address': addres,
          'vzipcode': zipcode,
          'country': country,
          'province': province,
          'district': district,
          'subdistrict': subdistrict,
          'taxStatus': _taxStatus ?? 'NO',
          'taxNo': _taxStatus == 'YES' ? taxNumber : 'null',
          'image': imageUrl,
          'faceImage': faceImageUrl,
          'idCardImage': idCardImageUrl,
          'idNumber': idNumber,
          'birthDate': birthDate,
          'cardOwnerName': cardOwnerName,
          'bankName': bankName,
          'bankAccount': bankAccount.isNotEmpty ? bankAccount : 'null',
          'promptPayId': promptPayId.isNotEmpty ? promptPayId : 'null',
          'qrCodeImage': qrImageUrl,
        };
        await updateVendorData(vendorData);
        EasyLoading.dismiss();
        Get.back(); // กลับไปหน้าก่อนหน้า
        Fluttertoast.showToast(
          msg: warningMsg.isEmpty
              ? 'อัปเดตโปรไฟล์สำเร็จ!'
              : 'อัปเดตสำเร็จ! $warningMsg (ข้อมูลพื้นฐานบันทึกแล้ว)',
        );
      } catch (e) {
        EasyLoading.dismiss();

        String errorMsg = e.toString();
        Fluttertoast.showToast(
          msg: 'เกิดข้อผิดพลาดในการอัปเดต: $errorMsg',
          backgroundColor: Colors.orange,
        );
      }
    }
  }

  String? _categoryDropdownValue;
  Future<void> getCategory() async {
    try {
      QuerySnapshot snapshot = await firestore.collection('categories').get();
      if (mounted) {
        setState(() {
          _categoryList.clear();
          for (var doc in snapshot.docs) {
            _categoryList.add(doc['categoryName'] as String? ?? 'Unknown');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _categoryList = ['Electronics', 'Food', 'Clothing'];
        });
      }
      Fluttertoast.showToast(
        msg: 'ไม่สามารถโหลดหมวดหมู่ได้: $e (ใช้ค่าเริ่มต้น)',
      );
    }
  }

  Future<void> selectQRCamera() async {
    Uint8List? img = await vendorController.pickStoreImage(ImageSource.camera);
    if (img.isNotEmpty) {
      if (img.lengthInBytes == 0) {
        Fluttertoast.showToast(msg: 'ไม่สามารถ pick รูปได้ กรุณาลองใหม่');
        return;
      }
      setState(() {
        qrImage = img;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Init ค่าเริ่มต้น
    WidgetsBinding.instance.addPostFrameCallback((_) {
      getCategory();
      _loadVendorData(); // โหลดข้อมูล
    });
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _ownerNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _taxNumberController.dispose();
    _bankAccountController.dispose();
    _promptPayIdController.dispose();
    _idNumberController.dispose();
    _birthDateController.dispose();
    _cardOwnerNameController.dispose();
    super.dispose();
  }

  Widget _buildImageWidget(
    String? url,
    Uint8List? bytes, {
    required String placeholderAsset,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    ImageProvider imageProvider;
    if (bytes != null) {
      imageProvider = MemoryImage(bytes);
    } else if (url != null && url.isNotEmpty) {
      imageProvider = CachedNetworkImageProvider(url);
    } else {
      imageProvider = AssetImage(placeholderAsset);
    }
    return Container(
      height: 100.h,
      width: 100.w,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10.r),
        image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
      ),
      child: bytes == null && url == null
          ? InkWell(
              onTap: onTap,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 40, color: Colors.grey),
                    Text(
                      label,
                      style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                height: 190.h,
                child: Center(
                  child: Stack(
                    children: [
                      Container(
                        height: 190.h,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(0),
                          image: DecorationImage(
                            image: image == null && currentImageUrl != null
                                ? CachedNetworkImageProvider(currentImageUrl!)
                                : (image != null
                                      ? MemoryImage(image!)
                                      : AssetImage('images/viewcover.jpg')),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: 100.w,
                              height: 100.h,
                              child: Stack(
                                alignment: Alignment.bottomLeft,
                                children: [
                                  ClipOval(
                                    child: Image(
                                      image:
                                          faceImage == null &&
                                              currentFaceImageUrl != null
                                          ? CachedNetworkImageProvider(
                                              currentFaceImageUrl!,
                                            )
                                          : (faceImage != null
                                                ? MemoryImage(faceImage!)
                                                : AssetImage(
                                                    'images/profile.jpg',
                                                  )),
                                      fit: BoxFit.cover,
                                      width: 100.w,
                                      height: 100.h,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              CircleAvatar(
                                                radius: 50,
                                                backgroundImage: AssetImage(
                                                  'images/profile.jpg',
                                                ),
                                              ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.cyan.shade400,
                                      radius: 18,
                                      child: IconButton(
                                        onPressed: () async {
                                          final result =
                                              await Navigator.push<Uint8List?>(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      const FaceScanPage(),
                                                ),
                                              );
                                          if (result != null && mounted) {
                                            setState(() {
                                              faceImage = result;
                                            });
                                            Fluttertoast.showToast(
                                              msg: 'อัปเดตสแกนใบหน้าเรียบร้อย!',
                                            );
                                          }
                                        },
                                        icon: Icon(
                                          Icons.face_retouching_natural,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 20,
                        child: CircleAvatar(
                          backgroundColor: Colors.cyan.shade400,
                          radius: 18.r,
                          child: IconButton(
                            onPressed: () => chooseOption(context),
                            icon: image != null
                                ? Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : Icon(
                                    CupertinoIcons.photo,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 30.h,
                        left: 20.w,
                        child: CircleAvatar(
                          radius: 20.sp,
                          backgroundColor: Colors.cyan.shade400,
                          child: IconButton(
                            icon: Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Get.back(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 12.h),
                    Text(
                      'แก้ไขข้อมูลร้าน',
                      style: styles(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: context.isDark ? Colors.cyan : Colors.black54,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Expanded(
                          child: _buildImageWidget(
                            currentIdCardImageUrl,
                            idCardImage,
                            placeholderAsset:
                                'images/id_placeholder.jpg', // สมมติมี asset นี้
                            icon: Icons.credit_card,
                            label: 'สแกนบัตรประชาชน',
                            onTap: () async {
                              final result =
                                  await Navigator.push<Map<String, dynamic>?>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const IdScanPage(),
                                    ),
                                  );
                              if (result != null && mounted) {
                                final file = File(result['path']!);
                                final bytes = await file.readAsBytes();
                                setState(() {
                                  idCardImage = bytes;
                                  idNumber =
                                      result['idNumber'] ??
                                      idNumber; // เก็บเก่าถ้าไม่มีใหม่
                                  birthDate = result['birthDate'] ?? birthDate;
                                  cardOwnerName =
                                      result['cardOwnerName'] ?? cardOwnerName;
                                  _idNumberController.text = idNumber;
                                  _birthDateController.text = birthDate;
                                  _cardOwnerNameController.text = cardOwnerName;
                                });
                                Fluttertoast.showToast(
                                  msg:
                                      'อัปเดตสแกนบัตรเรียบร้อย! ชื่อ: $cardOwnerName',
                                );
                              }
                            },
                          ),
                        ),
                        SizedBox(width: width * .4),
                      ],
                    ),
                    if (idCardImage != null ||
                        currentIdCardImageUrl != null) ...[
                      SizedBox(height: 10.h),
                      InputTextfield(
                        controller: _cardOwnerNameController,
                        hintText: 'ชื่อจากบัตร',
                        textInputType: TextInputType.text,
                        enabled: true,
                        prefixIcon: Icon(Icons.person, color: Colors.blue),
                        onChanged: (value) =>
                            setState(() => cardOwnerName = value),
                      ),
                      InputTextfield(
                        controller: _idNumberController,
                        hintText: 'เลขบัตรประชาชน',
                        textInputType: TextInputType.number,
                        enabled: true,
                        prefixIcon: Icon(Icons.credit_card, color: Colors.blue),
                        onChanged: (value) => setState(() => idNumber = value),
                        validator: (value) =>
                            value!.isEmpty || value.length != 13
                            ? 'เลขบัตรต้อง 13 หลัก'
                            : null,
                      ),
                      InputTextfield(
                        controller: _birthDateController,
                        hintText: 'วันเกิด',
                        textInputType: TextInputType.datetime,
                        enabled: true,
                        prefixIcon: Icon(Icons.cake, color: Colors.blue),
                        onChanged: (value) => setState(() => birthDate = value),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  children: [
                    // Category dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _categoryDropdownValue,
                      hint: const Text('เลือกหมวดหมู่'),
                      decoration: InputDecoration(
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.yellow.shade900,
                            width: 2,
                          ),
                        ),
                        errorBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.red, width: 2),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: context.isDark
                                ? Colors.white70
                                : Colors.grey,
                            width: 1,
                          ),
                        ),
                      ),
                      items: _categoryList.map((String category) {
                        return DropdownMenuItem<String>(
                          value: category,
                          child: Text(
                            category,
                            style: styles(
                              fontSize: 14.sp,
                              color: context.textColor,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _categoryDropdownValue = value),
                      validator: (value) =>
                          value == null ? 'กรุณาเลือกหมวดหมู่' : null,
                    ),
                    SizedBox(height: 20.h),

                    InputTextfield(
                      controller: _storeNameController,
                      hintText: 'ชื่อร้าน',
                      textInputType: TextInputType.text,
                      prefixIcon: Icon(
                        Icons.store,
                        color: Colors.yellow.shade900,
                      ),
                      onChanged: (value) => setState(() => name = value),
                      validator: (value) =>
                          value!.isEmpty ? 'กรุณากรอกชื่อร้าน' : null,
                    ),
                    InputTextfield(
                      controller: _emailController,
                      hintText: 'Email',
                      textInputType: TextInputType.emailAddress,
                      enabled: false,
                      prefixIcon: Icon(
                        Icons.email,
                        color: Colors.cyan.shade600,
                      ),
                      onChanged: (value) => setState(() => email = value),
                      validator: (value) => value!.isEmpty
                          ? 'Please enter your email address'
                          : (!value.isValidEmail() ? 'Invalid email' : null),
                    ),
                    InputTextfield(
                      controller: _phoneController,
                      hintText: 'เบอร์โทร',
                      textInputType: TextInputType.phone,
                      prefixIcon: Icon(
                        Icons.phone,
                        color: Colors.green.shade300,
                      ),
                      onChanged: (value) => setState(() => phone = value),
                      validator: (value) =>
                          value!.isEmpty ? 'Please Enter your Phone' : null,
                    ),
                    SizedBox(height: 10.h),
                    InputTextfield(
                      controller: _ownerNameController,
                      hintText: 'ชื่อเจ้าของร้าน',
                      textInputType: TextInputType.text,
                      prefixIcon: Icon(
                        Icons.person,
                        color: Colors.yellow.shade900,
                      ),
                      onChanged: (value) => setState(() => ownerName = value),
                      validator: (value) =>
                          value!.isEmpty ? 'กรุณากรอกชื่อเจ้าของร้าน' : null,
                    ),
                    SizedBox(height: 20.h),
                    // Bank dropdown
                    Padding(
                      padding: const EdgeInsets.only(left: 0, right: 0),
                      child: DropdownButtonFormField<String>(
                        initialValue: _bankDropdownValue,
                        hint: Text(
                          'เลือกธนาคาร',
                          style: styles(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w400,
                            color: context.textColor,
                          ),
                        ),
                        decoration: InputDecoration(
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.yellow.shade900,
                              width: 2,
                            ),
                          ),
                          errorBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.red, width: 2),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: context.isDark
                                  ? Colors.white70
                                  : Colors.grey,
                              width: 1,
                            ),
                          ),
                        ),
                        isExpanded: true,
                        items: _bankList.map((String bank) {
                          return DropdownMenuItem<String>(
                            value: bank,
                            child: SizedBox(
                              width: double.maxFinite,
                              child: Text(
                                bank,
                                overflow: TextOverflow.ellipsis,
                                style: styles(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w400,
                                  color: context.textColor,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            setState(() => _bankDropdownValue = value),
                        validator: (value) => null,
                      ),
                    ),
                    if (_bankDropdownValue != null) ...[
                      InputTextfield(
                        controller: _bankAccountController,
                        hintText: 'เลขบัญชี',
                        textInputType: TextInputType.number,
                        prefixIcon: const Icon(
                          Icons.account_balance,
                          color: Colors.blue,
                        ),
                        onChanged: (value) =>
                            setState(() => bankAccount = value),
                        validator: (value) => value!.isEmpty
                            ? 'เลขบัญชี'
                            : (value.length < 10
                                  ? 'เลขบัญชีต้องมีอย่างน้อย 10 หลัก'
                                  : null),
                      ),
                    ],
                    InputTextfield(
                      controller: _promptPayIdController,
                      hintText: 'PromptPay ID',
                      textInputType: TextInputType.phone,
                      prefixIcon: const Icon(
                        Icons.phone_android,
                        color: Colors.blue,
                      ),
                      onChanged: (value) => setState(() => promptPayId = value),
                      validator: (value) => null,
                    ),

                    if (_bankDropdownValue != null &&
                        _promptPayIdController.text.trim().isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 12.h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'QR Code แอปธนาคาร',
                              style: styles(
                                color: Colors.cyan.shade600,
                                fontSize: 14.sp,
                              ),
                            ),
                            SizedBox(height: 10.h),
                            Center(
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  _buildImageWidget(
                                    currentQrImageUrl,
                                    qrImage,
                                    placeholderAsset:
                                        'images/qr_placeholder.jpg',
                                    icon: Icons.qr_code,
                                    label: 'อัปโหลด QR Code',
                                    onTap: () => chooseQRImageOption(context),
                                  ),
                                  if (qrImage == null &&
                                      currentQrImageUrl == null)
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: CircleAvatar(
                                        backgroundColor: Colors.cyan.shade400,
                                        radius: 18.r,
                                        child: IconButton(
                                          onPressed: () =>
                                              chooseQRImageOption(context),
                                          icon: Icon(
                                            Icons.add_a_photo,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(height: 10.h),
                    InputTextfield(
                      controller: _addressController,
                      hintText: 'บ้านเลขที่',
                      textInputType: TextInputType.text,
                      prefixIcon: const Icon(
                        Icons.location_pin,
                        color: Colors.pink,
                      ),
                      onChanged: (value) => setState(() => addres = value),
                      validator: (value) => value!.isEmpty
                          ? 'กรุณากรอกบ้านเลขที่ หมู่ที่ '
                          : null,
                    ),

                    SizedBox(height: 12.h),
                    if (_addressLoaded)
                      ThaiAddressForm(
                        initialProvince: _initialProvince,
                        initialDistrict: _initialDistrict,
                        initialSubDistrict: _initialSubDistrict,
                        provinceDecoration: InputDecoration(
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.yellow.shade900,
                              width: 2,
                            ),
                          ),
                          errorBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.red, width: 2),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: context.isDark
                                  ? Colors.white70
                                  : Colors.grey,
                              width: 1,
                            ),
                          ),
                        ),
                        districtDecoration: InputDecoration(
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.yellow.shade900,
                              width: 2,
                            ),
                          ),
                          errorBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.red, width: 2),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: context.isDark
                                  ? Colors.white70
                                  : Colors.grey,
                              width: 1,
                            ),
                          ),
                        ),
                        subDistrictDecoration: InputDecoration(
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.yellow.shade900,
                              width: 2,
                            ),
                          ),
                          errorBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.red, width: 2),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: context.isDark
                                  ? Colors.white70
                                  : Colors.grey,
                              width: 1,
                            ),
                          ),
                        ),
                        zipCodeDecoration: InputDecoration(
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.yellow.shade900,
                              width: 2,
                            ),
                          ),
                          errorBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.red, width: 2),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: context.isDark
                                  ? Colors.white70
                                  : Colors.grey,
                              width: 1,
                            ),
                          ),
                        ),
                        textStyle: styles(
                          fontSize: 14.sp,
                          color: context.textColor,
                          fontWeight: FontWeight.w500,
                        ),
                        onChanged: (address) {
                          if ((address.provinceTh ?? '').isEmpty) return;
                          if ((address.districtTh ?? '').isEmpty) return;
                          if ((address.subDistrictTh ?? '').isEmpty) return;
                          if ((address.zipCode ?? '').isEmpty) return;
                          setState(() {
                            _selectedAddress = address;
                            province = address.provinceTh ?? '';
                            district = address.districtTh ?? '';
                            subdistrict = address.subDistrictTh ?? '';
                            zipcode = address.zipCode ?? '';
                          });
                        },
                        useThai: true,
                      )
                    else
                      SizedBox(
                        height: 200.h,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          flex: 2,
                          child: Text(
                            'จดทะเบียนบริษัท',
                            style: styles(
                              color: Colors.cyan.shade500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Flexible(
                          child: SizedBox(
                            width: 90,
                            child: DropdownButtonFormField(
                              initialValue: _taxStatus,
                              alignment: Alignment.center,
                              style: styles(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                contentPadding: EdgeInsets.zero,
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.yellow.shade900,
                                    width: 2,
                                  ),
                                ),
                                errorBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: context.isDark
                                        ? Colors.white70
                                        : Colors.grey,
                                    width: 1,
                                  ),
                                ),
                              ),
                              hint: Text(
                                'Select',
                                style: styles(
                                  color: Colors.cyan.shade600,
                                  fontSize: 14.sp,
                                ),
                              ),
                              items: _taxOptions
                                  .map<DropdownMenuItem<String>>(
                                    (String value) => DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(
                                        value,
                                        style: styles(
                                          color: Colors.deepOrange,
                                          fontSize: 14.sp,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _taxStatus = value),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_taxStatus == 'YES') ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6.w),
                        child: TextFormField(
                          controller: _taxNumberController,
                          keyboardType: TextInputType.number,
                          onChanged: (value) =>
                              setState(() => taxNumber = value),
                          validator: (value) => value!.isEmpty
                              ? 'Please Tax Number must not be empty'
                              : null,
                          decoration: InputDecoration(
                            labelText: 'เลขประจำตัวผู้เสียภาษี',
                            labelStyle: styles(color: Colors.cyan.shade600),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 70),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        bottom: true,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            left: 20.w,
            right: 20.w,
            bottom: MediaQuery.of(context).viewPadding.bottom + 12.h,
          ),
          child: ButtonWidget(
            label: 'อัปเดต',
            style: styles(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: Colors.white,
            ),
            icon: Icons.update,
            press: save,
          ),
        ),
      ),
    );
  }

  Future<dynamic> chooseOption(BuildContext context) {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Choose option',
            style: styles(
              fontWeight: FontWeight.w500,
              color: Colors.yellow.shade900,
            ),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                InkWell(
                  onTap: () {
                    selectCameca();
                    Navigator.pop(context);
                  },
                  splashColor: Colors.yellow.shade900,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.yellow.shade900,
                        ),
                      ),
                      Text(
                        'Camera',
                        style: styles(
                          fontWeight: FontWeight.w500,
                          color: Colors.cyan.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    selectGallery();
                    Navigator.pop(context);
                  },
                  splashColor: Colors.yellow.shade900,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.image_outlined,
                          color: Colors.green.shade900,
                        ),
                      ),
                      Text(
                        'Gallery',
                        style: styles(
                          fontWeight: FontWeight.w500,
                          color: Colors.cyan.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => removeImage('store'),
                  splashColor: Colors.yellow.shade900,
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.remove_circle, color: Colors.red),
                      ),
                      Text(
                        'Remove',
                        style: styles(
                          fontWeight: FontWeight.w500,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<dynamic> chooseQRImageOption(BuildContext context) {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('เลือก QR Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.yellow),
                title: const Text('Camera'),
                onTap: () {
                  selectQRCamera();
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('Gallery'),
                onTap: () {
                  selectQRGallery();
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle, color: Colors.red),
                title: const Text('Remove'),
                onTap: () {
                  removeImage('qr');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> selectQRGallery() async {
    Uint8List? img = await vendorController.pickStoreImage(ImageSource.gallery);
    if (img.isNotEmpty) {
      setState(() {
        qrImage = img;
      });
    }
  }

  Future<void> selectCameca() async {
    Uint8List? img = await vendorController.pickStoreImage(ImageSource.camera);
    if (img.isNotEmpty) {
      setState(() {
        image = img;
      });
    } else {
      Fluttertoast.showToast(msg: 'ไม่สามารถถ่ายรูปได้ กรุณาลองใหม่');
    }
  }

  Future<void> selectGallery() async {
    final img = await vendorController.pickStoreImage(ImageSource.gallery);
    if (img.isNotEmpty) {
      setState(() {
        image = img;
      });
    } else {
      Fluttertoast.showToast(msg: 'ไม่สามารถเลือกภาพได้ กรุณาลองใหม่');
    }
  }

  void removeImage(String type) {
    setState(() {
      switch (type) {
        case 'store':
          image = null;
          break;
        case 'qr':
          qrImage = null;
          break;
      }
    });
    Navigator.pop(context);
  }
}
