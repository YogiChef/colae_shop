// ignore_for_file: use_build_context_synchronously, avoid_print, unused_field
import 'dart:io'; // สำหรับ Fi
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
import 'package:colae_shop/auth/vendor_auth.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/widgets/button_widget.dart';
import 'package:colae_shop/widgets/input_textfield.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:colae_shop/main.dart';

class VendorRegistorPage extends StatefulWidget {
  const VendorRegistorPage({super.key});
  @override
  State<VendorRegistorPage> createState() => _VendorRegistorPageState();
}

class _VendorRegistorPageState extends State<VendorRegistorPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  ThaiAddress? _selectedAddress;
  String name = '';
  String ownerName = '';
  String email = '';
  String phone = '';
  String taxNumber = '';
  String addres = '';
  String zipcode = '';
  String countryValue = 'Thailand';
  String stateValue = '';
  String cityValue = '';
  String category = '';
  String bankName = '';
  String bankAccount = '';
  String promptPayId = '';
  // เพิ่มตัวแปรสำหรับข้อมูลบัตรประชาชน
  String idNumber = '';
  String birthDate = '';
  String cardOwnerName = '';
  Uint8List? image;
  Uint8List? faceImage;
  Uint8List? idCardImage;
  Uint8List? qrImage;
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
    'ธนาคาร ธกส (Bank for Agriculture)',
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
  final _referralCodeController = TextEditingController();
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
            if (retry < maxRetries) continue; // Retry
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
        if (e.code == 'object-not-found' && retry < maxRetries) {
          continue; // Retry on this error
        }
        return '';
      } catch (e) {
        if (retry < maxRetries) continue;
        return '';
      }
    }
    return '';
  }

  Future<void> saveVendorData(Map<String, dynamic> vendorData) async {
    try {
      String uid = _auth.currentUser!.uid;
      vendorData['vendorId'] = uid;
      vendorData['uid'] = uid;
      await FirebaseFirestore.instance.collection('vendors').doc(uid).set({
        ...vendorData,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
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
      if (idCardImage == null) {
        Fluttertoast.showToast(msg: 'กรุณาสแกนบัตรประชาชน');
        return;
      }
      if (idNumber.isEmpty) {
        Fluttertoast.showToast(msg: 'กรุณาสแกนบัตรให้ชัดเจนเพื่อดึงเลขบัตร');
        return;
      }
      if (ownerName.isNotEmpty && cardOwnerName.isNotEmpty) {
        String normOwner = ownerName.toLowerCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        String normCard = cardOwnerName.toLowerCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        String ownerFirst = normOwner.split(' ').first;
        String cardFirst = normCard.split(' ').first;
        if (!normOwner.contains(cardFirst) || !normCard.contains(ownerFirst)) {
          Fluttertoast.showToast(
            msg: 'ชื่อบันชีไม่ตรงกับบัตร (ตรวจ first name) กรุณาตรวจสอบ',
            timeInSecForIosWeb: 2,
          );
          return;
        }
      }
      if (faceImage == null) {
        Fluttertoast.showToast(msg: 'กรุณาสแกนใบหน้า');
        return;
      }
      if (name.isEmpty) {
        Fluttertoast.showToast(msg: 'กรุณากรอกชื่อร้าน');
        return;
      }
      if (ownerName.isEmpty) {
        Fluttertoast.showToast(msg: 'กรุณากรอกชื่อบันชี');
        return;
      }
      if (email.isEmpty) {
        Fluttertoast.showToast(msg: 'Email cannot be empty');
        return;
      }
      if (bankName.isNotEmpty &&
          bankAccount.isEmpty &&
          promptPayId.isEmpty &&
          qrImage == null) {
        Fluttertoast.showToast(
          msg: 'กรุณากรอกเลขบัญชี, PromptPay ID หรืออัปโหลด QR Code',
        );
        return;
      }
      EasyLoading.show(status: 'Please wait');
      try {
        await _auth.currentUser!.reload();
        String imageUrl = '';
        if (image != null && image!.isNotEmpty) {
          imageUrl = await uploadImagToStorage(image!, type: 'store');
          if (imageUrl.isEmpty) {}
        } else {}
        String faceImageUrl = '';
        if (faceImage != null && faceImage!.isNotEmpty) {
          faceImageUrl = await uploadImagToStorage(faceImage!, type: 'face');
          if (faceImageUrl.isEmpty) {}
        } else {}
        String idCardImageUrl = '';
        if (idCardImage != null && idCardImage!.isNotEmpty) {
          idCardImageUrl = await uploadImagToStorage(
            idCardImage!,
            type: 'idcard',
          );
          if (idCardImageUrl.isEmpty) {}
        } else {}
        String qrImageUrl = '';
        if (qrImage != null && qrImage!.isNotEmpty) {
          qrImageUrl = await uploadImagToStorage(qrImage!, type: 'qr');
          if (qrImageUrl.isEmpty) {}
        } else {}
        String warningMsg = '';
        if (imageUrl.isEmpty && image != null) warningMsg += 'รูปหน้าร้าน, ';
        if (faceImageUrl.isEmpty && faceImage != null) {
          warningMsg += 'รูปใบหน้า, ';
        }
        if (idCardImageUrl.isEmpty && idCardImage != null) {
          warningMsg += 'รูปบัตรประชาชน, ';
        }
        if (qrImageUrl.isEmpty && qrImage != null) {
          warningMsg += 'QR Code, ';
        }
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
          'vzipcode': _selectedAddress!.zipCode ?? '',
          'country': 'ประเทศไทย',
          'district': _selectedAddress!.districtTh ?? '',
          'subdistrict': _selectedAddress!.subDistrictTh ?? '',
          'province': _selectedAddress!.provinceTh ?? '',
          'taxStatus': _taxStatus ?? 'NO',
          'taxNo': _taxStatus == 'YES' ? taxNumber : 'null',
          'image': imageUrl,
          'faceImage': faceImageUrl,
          'idCardImage': idCardImageUrl,
          'idNumber': idNumber,
          'birthDate': birthDate,
          'cardOwnerName': cardOwnerName,
          'approved': false,
          'bankName': bankName,
          'bankAccount': bankAccount.isNotEmpty ? bankAccount : 'null',
          'promptPayId': promptPayId.isNotEmpty ? promptPayId : 'null',
          'qrCodeImage': qrImageUrl,
        };
        await saveVendorData(vendorData);
        final referralCode =
            _referralCodeController.text.trim().toUpperCase();
        if (referralCode.isNotEmpty) {
          try {
            final functions = FirebaseFunctions.instanceFor(
              region: 'asia-southeast1',
            );
            await functions.httpsCallable('registerReferral').call({
              'newUserId': _auth.currentUser!.uid,
              'referralCode': referralCode,
              'userType': 'vendor',
            });
          } catch (e) {
            debugPrint('[REFERRAL] error: $e');
          }
        } else {
          try {
            final functions = FirebaseFunctions.instanceFor(
              region: 'asia-southeast1',
            );
            await functions
                .httpsCallable('generateReferralCodeForUser')
                .call({
                  'userId': _auth.currentUser!.uid,
                  'userType': 'vendor',
                });
          } catch (e) {
            debugPrint('[REFERRAL-GEN] error: $e');
          }
        }
        if (_formKey.currentState != null) {
          _formKey.currentState!.reset();
        }
        _storeNameController.clear();
        _ownerNameController.clear();
        _emailController.clear();
        _phoneController.clear();
        _addressController.clear();
        _taxNumberController.clear();
        _bankAccountController.clear();
        _promptPayIdController.clear();
        _idNumberController.clear();
        _birthDateController.clear();
        _cardOwnerNameController.clear();
        image = null;
        faceImage = null;
        idCardImage = null;
        qrImage = null;
        idNumber = '';
        birthDate = '';
        cardOwnerName = '';
        EasyLoading.dismiss();
        Get.to(() => const VendorAuthPage());
        Fluttertoast.showToast(
          msg: warningMsg.isEmpty
              ? 'ลงทะเบียนสำเร็จ!'
              : 'ลงทะเบียนสำเร็จ! $warningMsg (ข้อมูลพื้นฐานบันทึกแล้ว)',
        );
      } catch (e) {
        EasyLoading.dismiss();

        String errorMsg = e.toString();
        Fluttertoast.showToast(
          msg: 'เกิดข้อผิดพลาดในการบันทึก: $errorMsg (ข้อมูลพื้นฐานบันทึกแล้ว)',
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
    try {
      final img = await vendorController.pickStoreImage(ImageSource.camera);

      if (img.lengthInBytes == 0) {
        Fluttertoast.showToast(msg: 'ไม่สามารถ pick รูปได้ กรุณาลองใหม่');
        return;
      }
      setState(() {
        qrImage = img;
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    name = '';
    ownerName = '';
    email = '';
    phone = '';
    taxNumber = '';
    addres = '';
    zipcode = '';
    countryValue = 'Thailand';
    stateValue = '';
    cityValue = '';
    category = '';
    bankName = '';
    bankAccount = '';
    promptPayId = '';
    idNumber = '';
    birthDate = '';
    cardOwnerName = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_auth.currentUser == null) {
        Get.to(() => const VendorAuthPage());
        return;
      }
      email = _auth.currentUser!.email ?? '';
      _emailController.text = email;
      getCategory();
      // Phase 4: รับ referralCode จาก deep link
      if (pendingReferralCode != null && pendingReferralCode!.isNotEmpty) {
        _referralCodeController.text = pendingReferralCode!;
        pendingReferralCode = null; // consume
      }
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
    _referralCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                            image: image == null
                                ? AssetImage('images/colae2.png')
                                : MemoryImage(image!),
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
                                  faceImage != null
                                      ? ClipOval(
                                          child: Image.memory(
                                            faceImage!,
                                            fit: BoxFit.cover,
                                            width: 100.w,
                                            height: 100.h,
                                          ),
                                        )
                                      : const CircleAvatar(
                                          radius: 50,
                                          backgroundImage: AssetImage(
                                            'images/profile.jpg',
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
                                              msg: 'สแกนใบหน้าเรียบร้อย!',
                                            );
                                          }
                                        },
                                        icon: const Icon(
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
                        top: 20,
                        left: 20,
                        child: CircleAvatar(
                          backgroundColor: Colors.cyan.shade400,
                          radius: 16.r,
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.arrow_back_ios,
                              size: 20.r,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 20,
                        child: CircleAvatar(
                          backgroundColor: Colors.cyan.shade400,
                          radius: 18.r,
                          child: IconButton(
                            onPressed: () {
                              chooseOption(context);
                            },
                            icon: image != null
                                ? const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : const Icon(
                                    CupertinoIcons.photo,
                                    color: Colors.white,
                                    size: 18,
                                  ),
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
                      'ข้อมูลร้าน',
                      style: styles(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 100.h,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(10.r),
                              image: idCardImage != null
                                  ? DecorationImage(
                                      image: MemoryImage(idCardImage!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              color: idCardImage == null
                                  ? Colors.grey.shade100
                                  : null,
                            ),
                            child: idCardImage == null
                                ? InkWell(
                                    onTap: () async {
                                      final result =
                                          await Navigator.push<
                                            Map<String, dynamic>?
                                          >(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const IdScanPage(),
                                            ),
                                          );
                                      if (result != null && mounted) {
                                        final file = File(result['path']!);
                                        final bytes = await file.readAsBytes();
                                        setState(() {
                                          idCardImage = bytes;
                                          idNumber = result['idNumber'] ?? '';
                                          birthDate = result['birthDate'] ?? '';
                                          cardOwnerName =
                                              result['cardOwnerName'] ?? '';
                                          _idNumberController.text = idNumber;
                                          _birthDateController.text = birthDate;
                                          _cardOwnerNameController.text =
                                              cardOwnerName;
                                        });

                                        Fluttertoast.showToast(
                                          msg:
                                              'สแกนสำเร็จและยืนยันข้อมูล! ชื่อ: $cardOwnerName',
                                        );
                                      }
                                    },
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.credit_card,
                                            size: 40,
                                            color: Colors.grey,
                                          ),
                                          Text(
                                            'สแกนบัตรประชาชน',
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        SizedBox(width: width * .4),
                      ],
                    ),

                    if (idCardImage != null) ...[
                      SizedBox(height: 10.h),
                      InputTextfield(
                        controller: _cardOwnerNameController,
                        hintText: 'ชื่อจากบัตร (auto)',
                        textInputType: TextInputType.text,
                        enabled: false,
                        prefixIcon: Icon(Icons.person, color: Colors.blue),
                        onChanged: (value) =>
                            setState(() => cardOwnerName = value),
                      ),
                      InputTextfield(
                        controller: _idNumberController,
                        hintText: 'เลขบัตรประชาชน (auto)',
                        textInputType: TextInputType.number,
                        enabled: false,
                        prefixIcon: Icon(Icons.credit_card, color: Colors.blue),
                        onChanged: (value) => setState(() => idNumber = value),
                        validator: (value) =>
                            value!.isEmpty || value.length != 13
                            ? 'เลขบัตรต้อง 13 หลัก'
                            : null,
                      ),
                      InputTextfield(
                        controller: _birthDateController,
                        hintText: 'วันเกิด (auto)',
                        textInputType: TextInputType.datetime,
                        enabled: false,
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
                    DropdownButtonFormField<String>(
                      padding: EdgeInsets.zero,
                      initialValue: _categoryDropdownValue,
                      hint: const Text('เลือกหมวดหมู่'),
                      items: _categoryList.map((String category) {
                        return DropdownMenuItem<String>(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _categoryDropdownValue = value),
                      validator: (value) =>
                          value == null ? 'กรุณาเลือกหมวดหมู่' : null,
                    ),
                    SizedBox(height: 20.h),
                    // ชื่อร้าน
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
                      hintText: 'ชื่อบันชี',
                      textInputType: TextInputType.text,
                      prefixIcon: Icon(
                        Icons.person,
                        color: Colors.yellow.shade900,
                      ),
                      onChanged: (value) => setState(() => ownerName = value),
                      validator: (value) => value!.isEmpty
                          ? 'กรุณากรอกชื่อเจ้าของบันขีให้ตรงกับสมุดบันชี'
                          : null,
                    ),
                    SizedBox(height: 20.h),
                    Padding(
                      padding: const EdgeInsets.only(left: 0, right: 0),
                      child: DropdownButtonFormField<String>(
                        initialValue: _bankDropdownValue,
                        hint: const Text('เลือกธนาคาร'),
                        isExpanded: true,
                        items: _bankList.map((String bank) {
                          return DropdownMenuItem<String>(
                            value: bank,
                            child: SizedBox(
                              width: double.maxFinite,
                              child: Text(
                                bank,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
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
                    // QR upload if needed
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
                                  qrImage != null
                                      ? Container(
                                          height: 100.h,
                                          width: 100.w,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              10.r,
                                            ),
                                            image: DecorationImage(
                                              image: MemoryImage(qrImage!),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        )
                                      : Container(
                                          height: 100.h,
                                          width: 100.w,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade300,
                                            borderRadius: BorderRadius.circular(
                                              10.r,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.qr_code,
                                            size: 50.r,
                                            color: Colors.grey,
                                          ),
                                        ),
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
                                          size: 18.r,
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

                    ThaiAddressForm(
                      textStyle: styles(
                        fontSize: 14.sp,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),

                      onChanged: (address) {
                        setState(() {});
                        if ((address.provinceTh ?? '').isEmpty) return;
                        if ((address.districtTh ?? '').isEmpty) return;
                        if ((address.subDistrictTh ?? '').isEmpty) {
                          return;
                        }
                        if ((address.zipCode ?? '').isEmpty) return;
                        setState(() => _selectedAddress = address);
                      },
                      useThai: true,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tax Registered?',
                          style: styles(
                            color: Colors.cyan.shade600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: SizedBox(
                            width: 100,
                            child: DropdownButtonFormField(
                              hint: Text(
                                'Select',
                                style: styles(
                                  color: Colors.cyan.shade600,
                                  fontSize: 16,
                                ),
                              ),
                              items: _taxOptions
                                  .map<DropdownMenuItem<String>>(
                                    (String value) => DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(
                                        value,
                                        style: styles(color: Colors.deepOrange),
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
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextFormField(
                          keyboardType: TextInputType.number,
                          onChanged: (value) =>
                              setState(() => taxNumber = value),
                          validator: (value) => value!.isEmpty
                              ? 'Please Tax Number must not be empty'
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Tax Number',
                            labelStyle: styles(color: Colors.cyan.shade600),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _referralCodeController,
                      decoration: const InputDecoration(
                        labelText: 'รหัสแนะนำ (ถ้ามี)',
                        prefixIcon: Icon(Icons.card_giftcard),
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
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
            bottom: MediaQuery.of(context).viewPadding.bottom + 12.h,
            left: 20.w,
            right: 20.w,
          ),
          child: ButtonWidget(
            label: 'Save',
            style: styles(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: Colors.white,
            ),
            icon: Icons.save,
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
                  onTap: () {
                    remove();
                  },
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
            ],
          ),
        );
      },
    );
  }

  Future<void> selectQRGallery() async {
    try {
      final img = await vendorController.pickStoreImage(ImageSource.gallery);
      setState(() {
        qrImage = img;
      });
    } catch (_) {}
  }

  Future<void> selectCameca() async {
    try {
      final img = await vendorController.pickStoreImage(ImageSource.camera);

      setState(() {
        image = img;
      });
    } catch (_) {
      Fluttertoast.showToast(msg: 'ไม่สามารถถ่ายรูปได้ กรุณาลองใหม่');
    }
  }

  Future<void> selectGallery() async {
    try {
      final img = await vendorController.pickStoreImage(ImageSource.gallery);

      setState(() {
        image = img;
      });
    } catch (_) {
      Fluttertoast.showToast(msg: 'ไม่สามารถเลือกภาพได้ กรุณาลองใหม่');
    }
  }

  void remove() {
    setState(() {
      image = null;
    });
    Navigator.pop(context);
  }
}
