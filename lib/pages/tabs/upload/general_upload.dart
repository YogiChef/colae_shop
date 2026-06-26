// ignore_for_file: depend_on_referenced_packages, no_leading_underscores_for_local_identifiers, deprecated_member_use, unnecessary_cast

import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colae_shop/pages/tabs/upload/barcode_scanner_page.dart';
import 'package:colae_shop/pages/tabs/upload/type.dart';
import 'package:colae_shop/providers/product_provider.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/widgets/button_widget.dart';
import 'package:colae_shop/widgets/input_textfield.dart';

class GeneralUpload extends StatefulWidget {
  const GeneralUpload({super.key});

  @override
  State<GeneralUpload> createState() => _GeneralUploadState();
}

class _GeneralUploadState extends State<GeneralUpload>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  bool get wantKeepAlive => true;
  final List<String> _categoryList = [];
  List<File> _image = [];
  final List<String> _imageUrlList = [];
  final ImagePicker picker = ImagePicker();
  DateTime? _scheduleDate;
  String _saleMode = 'delivery';
  List<Map<String, TextEditingController>> _tierControllers = [];
  final TextEditingController _extraBaseController = TextEditingController(
    text: '0',
  );
  final TextEditingController _extraPerUnitController = TextEditingController(
    text: '0',
  );
  final TextEditingController _shippingNoteController = TextEditingController();
  String? _scannedBarcode;
  String? _selectedType;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _promptpayNumberController =
      TextEditingController();
  final TextEditingController _promptpayNameController =
      TextEditingController();

  String _defaultCarrier = 'Kerry';
  final TextEditingController _customCarrierController =
      TextEditingController();
  final List<String> _carriers = [
    'Kerry',
    'Flash',
    'J&T',
    'Thai Post',
    'อื่นๆ',
  ];
  Future<void> _loadCarrier() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await _firestore.collection('vendors').doc(uid).get();
    if (!doc.exists || !mounted) return;
    final data = doc.data() ?? {};
    final saved = data['defaultCarrier'] as String? ?? 'Kerry';
    final pp = (data['promptpay'] as Map<String, dynamic>?) ?? {};
    setState(() {
      if (_carriers.contains(saved)) {
        _defaultCarrier = saved;
      } else {
        _defaultCarrier = 'อื่นๆ';
        _customCarrierController.text = saved;
      }
      _promptpayNumberController.text = pp['number'] as String? ?? '';
      _promptpayNameController.text = pp['accountName'] as String? ?? '';
    });
  }

  // Package
  String _selectedPackage = 'ห่อ';
  final TextEditingController _customPackageController =
      TextEditingController();
  final TextEditingController _packageQtyController = TextEditingController(
    text: '1',
  );
  final List<String> _packageOptions = [
    'ห่อ',
    'กล่อง',
    'ขวด',
    'ถุง',
    'กระป๋อง',
    'แพ็ค',
    'ลัง',
    'ปี๊ป',
    'กระสอบ',
    'อื่นๆ',
  ];

  // Unit
  String _selectedUnit = 'กรัม';
  final TextEditingController _customUnitController = TextEditingController();
  final TextEditingController _unitSizeController = TextEditingController();
  final List<String> _unitOptions = [
    'กรัม',
    'กก.',
    'มล.',
    'ลิตร',
    'ชิ้น',
    'ลูก',
    'เม็ด',
    'อื่นๆ',
  ];

  void _addTier({
    int qtyFrom = 1,
    int qtyTo = 5,
    double fee = 0,
    bool rebuild = true,
  }) {
    final entry = {
      'qtyFrom': TextEditingController(text: qtyFrom.toString()),
      'qtyTo': TextEditingController(text: qtyTo.toString()),
      'fee': TextEditingController(text: fee.toStringAsFixed(0)),
    };
    if (rebuild) {
      setState(() => _tierControllers.add(entry));
    } else {
      _tierControllers.add(entry);
    }
  }

  void _removeTier(int index) {
    final tier = _tierControllers[index];
    tier['qtyFrom']?.dispose();
    tier['qtyTo']?.dispose();
    tier['fee']?.dispose();
    setState(() => _tierControllers.removeAt(index));
  }

  Future<void> getType() async {
    final snapshot = await firestore.collection('type').get();
    final types = snapshot.docs
        .map((doc) => doc['typename'] as String)
        .toList();
    if (mounted) {
      setState(() {
        _categoryList.clear();
        _categoryList.addAll(types);
      });
    }
  }

  Future<void> choosGallery() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) {
      Fluttertoast.showToast(msg: 'No image picked');
    } else {
      setState(() {
        _image.add(File(pickedFile.path));
      });
    }
  }

  Future<void> choosCamera() async {
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile == null) {
      Fluttertoast.showToast(msg: 'No image picked');
    } else {
      setState(() {
        _image.add(File(pickedFile.path));
      });
    }
  }

  void _addGroupDialog() {
    final groupNameController = TextEditingController();
    OptionGroupType? selectedType;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'เพิ่มกลุ่มตัวเลือก',
            style: styles(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: context.textColor,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: groupNameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อกลุ่ม ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<OptionGroupType>(
                value: selectedType,
                decoration: const InputDecoration(
                  labelText: 'ประเภทกลุ่ม',
                  border: OutlineInputBorder(),
                ),
                items: OptionGroupType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.label, style: styles(fontSize: 14.sp)),
                  );
                }).toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedType = value;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'ยกเลิก',
                style: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  color: context.textColor,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                if (selectedType != null) {
                  final provider = Provider.of<ProductProvider>(
                    context,
                    listen: false,
                  );
                  provider.addOptionGroup(
                    selectedType!,
                    groupName: groupNameController.text.trim().isEmpty
                        ? null
                        : groupNameController.text.trim(),
                  );
                  Navigator.pop(context);
                  Fluttertoast.showToast(msg: 'เพิ่มกลุ่มสำเร็จ!');
                } else {
                  Fluttertoast.showToast(
                    msg: 'กรุณาเลือกประเภทกลุ่ม',
                    backgroundColor: Colors.red,
                  );
                }
              },
              child: Text(
                'เพิ่ม',
                style: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  color: context.textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addOptionToGroupDialog(int groupIndex) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final provider = Provider.of<ProductProvider>(context, listen: false);
    final groupType = provider.optionGroups[groupIndex]['type'] as String;
    final isFree = groupType == 'free';
    if (isFree) {
      priceController.text = '0';
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'เพิ่มตัวเลือกในกลุ่ม: ${provider.optionGroups[groupIndex]['name'] ?? provider.optionGroups[groupIndex]['type']}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'ชื่อตัวเลือก',
                labelStyle: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  color: context.textColor,
                ),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceController,
              keyboardType: isFree ? TextInputType.none : TextInputType.number,
              readOnly: isFree,
              decoration: InputDecoration(
                labelText: isFree ? 'ฟรี' : 'ราคาเพิ่ม',
                labelStyle: styles(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  color: context.textColor,
                ),
                border: const OutlineInputBorder(),
                suffixText: isFree ? '฿0' : '฿',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final price = isFree
                  ? 0.0
                  : (double.tryParse(priceController.text.trim()) ?? 0.0);
              if (name.isNotEmpty) {
                provider.addOptionToGroup(groupIndex, {
                  'name': name,
                  'price': price,
                });
                Navigator.pop(context);
                Fluttertoast.showToast(msg: 'เพิ่มตัวเลือกสำเร็จ!');
              } else {
                Fluttertoast.showToast(
                  msg: 'กรุณากรอกชื่อตัวเลือก',
                  backgroundColor: Colors.red,
                );
              }
            },
            child: Text(
              'เพิ่ม',
              style: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: context.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final tier in _tierControllers) {
      tier['qtyFrom']?.dispose();
      tier['qtyTo']?.dispose();
      tier['fee']?.dispose();
    }
    _extraBaseController.dispose();
    _extraPerUnitController.dispose();
    _shippingNoteController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    _descController.dispose();
    _customPackageController.dispose();
    _packageQtyController.dispose();
    _customUnitController.dispose();
    _unitSizeController.dispose();
    _customCarrierController.dispose();
    _promptpayNumberController.dispose();
    _promptpayNameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tierControllers = [];
    _addTier(qtyFrom: 1, qtyTo: 5, fee: 0, rebuild: false);
    getType();
    _loadCarrier();
  }

  Future<void> _openBarcodeScanner() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (result == null || result.isEmpty || !mounted) return;

    setState(() => _scannedBarcode = result);

    EasyLoading.show(status: 'กำลังค้นหา...');
    try {
      final doc = await firestore
          .collection('products_master')
          .doc(result)
          .get();
      EasyLoading.dismiss();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        _autoFillFromMaster(data, result);
        Fluttertoast.showToast(
          msg: 'พบสินค้า: ${data['proName'] ?? '-'}',
          backgroundColor: Colors.green,
          toastLength: Toast.LENGTH_SHORT,
        );
      } else {
        Fluttertoast.showToast(
          msg: 'ไม่พบสินค้า — กรุณากรอกข้อมูลเอง\nบาร์โค้ด: $result',
          backgroundColor: Colors.orange,
          toastLength: Toast.LENGTH_LONG,
        );
      }
    } catch (e) {
      EasyLoading.dismiss();
      EasyLoading.showError('ผิดพลาด: $e');
    }
  }

  void _autoFillFromMaster(Map<String, dynamic> data, String barcode) {
    final provider = Provider.of<ProductProvider>(context, listen: false);
    final name = data['proName']?.toString() ?? '';
    final desc = data['description']?.toString() ?? '';
    final type = data['type']?.toString();

    if (name.isNotEmpty) {
      _nameController.text = name;
      provider.getFormData(productName: name, notify: false);
    }
    if (desc.isNotEmpty) {
      _descController.text = desc;
      provider.getFormData(description: desc, notify: false);
    }
    setState(() {
      _scannedBarcode = barcode;
      if (type != null && _categoryList.contains(type)) {
        _selectedType = type;
        provider.getFormData(type: type, notify: false);
      }

      final pkg = data['package']?.toString() ?? '';
      if (pkg.isNotEmpty) {
        if (_packageOptions.contains(pkg)) {
          _selectedPackage = pkg;
        } else {
          _selectedPackage = 'อื่นๆ';
          _customPackageController.text = pkg;
        }
      }
      _packageQtyController.text = (data['packageQty'] ?? 1).toString();

      final unit = data['unit']?.toString() ?? '';
      if (unit.isNotEmpty) {
        if (_unitOptions.contains(unit)) {
          _selectedUnit = unit;
        } else {
          _selectedUnit = 'อื่นๆ';
          _customUnitController.text = unit;
        }
      }
      _unitSizeController.text = (data['unitSize'] ?? '').toString();
    });
    provider.getFormData();
    Fluttertoast.showToast(msg: 'กรุณาตั้งราคาขายและจำนวนสินค้าของร้าน');
  }

  String formatedDate(DateTime date) {
    final outPutDateFormate = DateFormat('dd/MM/yyyy');
    final outPutDate = outPutDateFormate.format(date);
    return outPutDate;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SingleChildScrollView(
        child: Consumer<ProductProvider>(
          builder: (context, provider, child) {
            final bool isFormValid = provider.isFormValid();
            final bool hasImages =
                _image.isNotEmpty ||
                (provider.productData['imageUrlList'] as List?)?.isNotEmpty ==
                    true;
            final bool showSaveButton = isFormValid && hasImages;

            return Form(
              key: _formKey,
              child: Padding(
                padding: EdgeInsets.only(right: 20.w, left: 20.w, bottom: 20.h),
                child: Column(
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      itemCount: _image.length + 1,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.4,
                            crossAxisSpacing: 8,
                          ),
                      itemBuilder: (context, index) {
                        return index == 0
                            ? Material(
                                elevation: 0,
                                color: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(7.r),
                                  side: BorderSide(
                                    color: context.isDark
                                        ? Colors.white70
                                        : Colors.grey.shade400,
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        onPressed: () {
                                          chooseOption(context);
                                        },
                                        icon: Icon(
                                          CupertinoIcons
                                              .photo_fill_on_rectangle_fill,
                                          size: 34.r,
                                          color: context.isDark
                                              ? mainColor
                                              : Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        'รูปภาพ',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.righteous(
                                          fontSize: 14.sp,
                                          color: context.isDark
                                              ? mainColor
                                              : Colors.grey,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      image: DecorationImage(
                                        image: FileImage(_image[index - 1]),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _image.removeAt(index - 1);
                                        });
                                      },
                                      icon: Icon(
                                        IconlyLight.delete,
                                        color: Colors.red,
                                        size: 20.r,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                      },
                    ),
                    SizedBox(height: 20.h),
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _openBarcodeScanner,
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: context.isDark
                                    ? Colors.white70
                                    : Colors.grey.shade400,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(
                                Icons.qr_code_scanner,
                                color: context.textColor,
                                size: 18.sp,
                              ),
                              SizedBox(width: 8.w),
                              Text(
                                _scannedBarcode != null
                                    ? '$_scannedBarcode '
                                    : 'สแกนบาร์โค้ด',
                                style: styles(
                                  color: context.textColor,
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _selectedType,
                      padding: EdgeInsets.only(
                        left: 20.w,
                        right: 20.w,
                        top: 4.h,
                        bottom: 4.h,
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down),
                      decoration: InputDecoration(
                        prefixIcon: IconButton(
                          icon: const Icon(Icons.inventory),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const TypeTab(),
                              ),
                            );
                            await getType();
                          },
                        ),
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
                      hint: Text(
                        'ประเภทสินค้า',
                        style: styles(
                          fontSize: 12.sp,
                          color: context.textColor,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      items: _categoryList.map<DropdownMenuItem<String>>((e) {
                        return DropdownMenuItem(
                          value: e,
                          child: Text(
                            e,
                            style: styles(
                              fontSize: 12.sp,
                              color: context.textColor,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedType = value);
                          provider.getFormData(type: value);
                        }
                      },
                      validator: (value) =>
                          value == null ? 'กรุณาเลือกประเภทสินค้า' : null,
                    ),
                    InputTextfield(
                      textInputType: TextInputType.text,
                      prefixIcon: const Icon(Icons.drive_file_rename_outline),

                      hintText: 'ชื่อสินค้า',
                      controller: _nameController,
                      validator: (value) {
                        if (value!.isEmpty) {
                          return 'Please enter product name';
                        } else {
                          return null;
                        }
                      },
                      onChanged: (value) {
                        provider.getFormData(productName: value);
                      },
                    ),
                    InputTextfield(
                      textInputType: TextInputType.number,
                      prefixIcon: const Icon(Icons.money_sharp),
                      hintText: 'ราคาสินค้า',
                      controller: _priceController,
                      validator: (value) {
                        if (value!.isEmpty) {
                          return 'Please enter product price';
                        }
                        final price = double.tryParse(value);
                        if (price == null || price <= 0) {
                          return 'Price must be greater than 0';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        provider.getFormData(
                          productPrice: double.tryParse(value) ?? 0.0,
                        );
                      },
                    ),
                    if (_scannedBarcode != null) ...[
                      SizedBox(height: 16.h),
                      Row(
                        children: [
                          Icon(
                            Icons.inventory_2,
                            size: 16.sp,
                            color: Colors.grey[700],
                          ),
                          SizedBox(width: 6.w),
                          Text(
                            'หน่วยบรรจุ',
                            style: styles(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: context.subColor,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.w),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                value: _selectedPackage,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'แบบ',
                                  border: const UnderlineInputBorder(),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                      color: mainColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                items: _packageOptions
                                    .map(
                                      (p) => DropdownMenuItem(
                                        value: p,
                                        child: Text(
                                          p,
                                          style: styles(
                                            fontSize: 13.sp,
                                            color: context.textColor,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  setState(() => _selectedPackage = v ?? 'ห่อ');
                                },
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _packageQtyController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'จำนวน',
                                  hintText: '1',
                                  border: UnderlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_selectedPackage == 'อื่นๆ') ...[
                        SizedBox(height: 8.h),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.w),
                          child: TextField(
                            controller: _customPackageController,
                            decoration: InputDecoration(
                              labelText: 'ระบุหน่วยบรรจุ',
                              hintText: 'เช่น แพ็คคู่ / โหล',
                              border: const UnderlineInputBorder(),
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
                          ),
                        ),
                      ],
                      SizedBox(height: 16.h),
                      // ปริมาณ section
                      Row(
                        children: [
                          Icon(
                            Icons.scale_outlined,
                            size: 16.sp,
                            color: Colors.grey[700],
                          ),
                          SizedBox(width: 6.w),
                          Text(
                            'ปริมาณ',
                            style: styles(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: context.subColor,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.w),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _unitSizeController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'ขนาด',
                                  hintText: '60',
                                  border: UnderlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                value: _selectedUnit,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'หน่วย',
                                  labelStyle: styles(
                                    fontSize: 13.sp,
                                    color: context.textColor,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  border: const UnderlineInputBorder(),
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
                                items: _unitOptions
                                    .map(
                                      (u) => DropdownMenuItem(
                                        value: u,
                                        child: Text(
                                          u,
                                          style: styles(
                                            fontSize: 11.sp,
                                            color: context.textColor,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  setState(() => _selectedUnit = v ?? 'กรัม');
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_selectedUnit == 'อื่นๆ') ...[
                        SizedBox(height: 8.h),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.w),
                          child: TextField(
                            controller: _customUnitController,
                            decoration: InputDecoration(
                              labelText: 'ระบุหน่วย',
                              hintText: 'เช่น ออนซ์ / แก้ว',
                              border: const UnderlineInputBorder(),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: mainColor,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                    SizedBox(height: 12.h),
                    Transform.scale(
                      scale: 0.85,
                      child: SwitchListTile(
                        title: Text(
                          'ตัดสต๊อก',
                          style: styles(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: context.textColor,
                          ),
                        ),
                        subtitle: Text(
                          provider.trackStock
                              ? 'จำกัดจำนวน — ตัดสต๊อกอัตโนมัติเมื่อขาย'
                              : 'ไม่จำกัดจำนวน — เหมาะกับอาหาร/บริการ',
                          style: styles(
                            fontSize: 11.sp,
                            color: context.subColor,
                          ),
                        ),
                        value: provider.trackStock,
                        onChanged: (val) => provider.setTrackStock(val),
                        activeColor: mainColor,
                        activeTrackColor: Colors.grey[200],
                        inactiveTrackColor: Colors.grey[200],
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (provider.trackStock) ...[
                      SizedBox(height: 8.h),
                      InputTextfield(
                        textInputType: TextInputType.number,
                        prefixIcon: const Icon(Icons.qr_code),
                        hintText: 'จำนวน',
                        controller: _qtyController,
                        validator: (value) {
                          if (value!.isEmpty) {
                            return 'Please enter product quantity';
                          }
                          final qty = int.tryParse(value);
                          if (qty == null || qty <= 0) {
                            return 'Quantity must be greater than 0';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          provider.getFormData(qty: int.tryParse(value) ?? 0);
                        },
                      ),
                    ],
                    TextFormField(
                      controller: _descController,
                      keyboardType: TextInputType.text,
                      maxLength: 400,
                      maxLines: 2,
                      validator: (value) {
                        if (value!.isEmpty) {
                          return 'Please enter product description';
                        } else {
                          return null;
                        }
                      },
                      decoration: InputDecoration(
                        border: UnderlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                        labelText: 'รายละเอียดสินค้า',
                        labelStyle: styles(color: context.textColor),
                        errorBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.red, width: 2),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.yellow.shade900,
                            width: 2,
                          ),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: context.isDark
                                ? Colors.white70
                                : Colors.grey,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        provider.getFormData(description: value);
                      },
                    ),
                    ExpansionTile(
                      shape: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: context.isDark ? Colors.white70 : Colors.grey,
                        ),
                      ),
                      title: Text(
                        'ตัวเลือกเมนู',
                        style: styles(
                          fontSize: 14.sp,
                          color: context.textColor,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      subtitle: Text(
                        provider.optionGroups.isEmpty
                            ? ''
                            : '${provider.optionGroups.length} กลุ่ม',
                      ),
                      leading: const Icon(Icons.menu_book),
                      children: [
                        ...provider.optionGroups.asMap().entries.map((entry) {
                          int groupIndex = entry.key;
                          Map<String, dynamic> group = entry.value;
                          final groupType = group['type'] as String;
                          final groupTypeEnum = OptionGroupType.values
                              .firstWhere(
                                (e) => e.name == groupType,
                                orElse: () => OptionGroupType.free,
                              );
                          final groupName =
                              group['name'] ?? groupType.toUpperCase();
                          final options =
                              group['options'] as List<Map<String, dynamic>>;
                          return ExpansionTile(
                            key: ValueKey(groupIndex),
                            title: Text(groupName),
                            subtitle: Text(
                              '${groupTypeEnum.label} / ${options.length} ตัวเลือก',
                              style: styles(
                                fontSize: 13.sp,
                                color: context.textColor,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            leading: Icon(
                              _getGroupIcon(groupType),
                              color: _getGroupColor(groupType),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_forever,
                                color: Colors.red,
                              ),
                              onPressed: () {
                                provider.removeOptionGroup(groupIndex);
                                Fluttertoast.showToast(msg: 'ลบกลุ่มสำเร็จ!');
                              },
                            ),
                            children: [
                              ...options.asMap().entries.map((optEntry) {
                                int optIndex = optEntry.key;
                                Map<String, dynamic> option = optEntry.value;
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    option['name'],
                                    style: styles(
                                      fontSize: 14.sp,
                                      color: context.textColor,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  subtitle: Text(
                                    option['price'] == 0
                                        ? 'ฟรี'
                                        : '+฿${option['price']}',
                                    style: styles(
                                      fontSize: 14.sp,
                                      color: context.textColor,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                    onPressed: () =>
                                        provider.removeOptionFromGroup(
                                          groupIndex,
                                          optIndex,
                                        ),
                                  ),
                                );
                              }),
                              ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.green,
                                ),
                                title: Text(
                                  'เพิ่มตัวเลือก',
                                  style: styles(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.sp,
                                    color: context.textColor,
                                  ),
                                ),
                                onTap: () =>
                                    _addOptionToGroupDialog(groupIndex),
                              ),
                            ],
                          );
                        }),
                        ListTile(
                          leading: const Icon(
                            Icons.add,
                            color: Colors.deepOrange,
                          ),
                          title: Text(
                            'เพิ่มกลุ่มตัวเลือกใหม่',
                            style: styles(
                              fontWeight: FontWeight.w500,
                              fontSize: 13.sp,
                              color: context.textColor,
                            ),
                          ),
                          onTap: _addGroupDialog,
                        ),
                      ],
                    ),

                    SizedBox(height: 12.h),
                    DropdownButtonFormField<String>(
                      value: _saleMode,
                      isExpanded: true,
                      padding: EdgeInsets.zero,
                      decoration: InputDecoration(
                        labelText: 'รูปแบบสินค้า',
                        border: const UnderlineInputBorder(),
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
                        contentPadding: EdgeInsets.symmetric(vertical: 8.h),
                        helperText: 'ส่งใกล้ร้าน,ส่งทั่วประเทศ',
                        helperMaxLines: 2,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'delivery',
                          child: Text(
                            '🛵 Delivery',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'ecommerce',
                          child: Text(
                            '📦 Ecommerce',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _saleMode = v ?? 'delivery');
                      },
                    ),
                    if (_saleMode == 'ecommerce') ...[
                      DropdownButtonFormField<String>(
                        initialValue: _defaultCarrier,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: UnderlineInputBorder(),
                          fillColor: mainColor,
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
                        items: _carriers
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c,
                                  style: styles(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w400,
                                    color: context.isDark
                                        ? Colors.deepPurple[900]
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() => _defaultCarrier = v ?? 'Kerry');
                          _saveCarrier();
                        },
                      ),
                      if (_defaultCarrier == 'อื่นๆ') ...[
                        SizedBox(height: 8.h),
                        TextField(
                          controller: _customCarrierController,
                          style: styles(
                            color: context.textColor,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: 'ชื่อขนส่ง',

                            border: UnderlineInputBorder(),
                          ),
                          onChanged: (_) => _saveCarrier(),
                        ),
                      ],
                      SizedBox(height: 12.h),
                      Text(
                        'ค่าส่ง',
                        style: styles(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: context.textColor,
                        ),
                      ),

                      SizedBox(height: 20.h),
                      ...List.generate(_tierControllers.length, (i) {
                        final tier = _tierControllers[i];
                        return Row(
                          children: [
                            Text(
                              'ขั้น ${i + 1}:',
                              style: styles(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                                color: context.subColor,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: TextField(
                                controller: tier['qtyFrom'],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: styles(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w400,
                                  color: context.textColor,
                                ),
                                decoration: InputDecoration(
                                  label: Text(
                                    'จาก',
                                    style: styles(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w400,
                                      color: context.textColor,
                                    ),
                                  ),

                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12.h,
                                  ),
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
                              ),
                            ),
                            SizedBox(width: 20.w),

                            Expanded(
                              child: TextField(
                                controller: tier['qtyTo'],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: styles(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w400,
                                  color: context.textColor,
                                ),
                                decoration: InputDecoration(
                                  label: Text(
                                    'ถึง',
                                    style: styles(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w400,
                                      color: context.textColor,
                                    ),
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12.h,
                                  ),
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
                              ),
                            ),
                            SizedBox(width: 20.w),

                            Expanded(
                              child: TextField(
                                controller: tier['fee'],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: styles(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w400,
                                  color: context.textColor,
                                ),
                                decoration: InputDecoration(
                                  label: Text(
                                    'ค่าส่ง',
                                    style: styles(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w400,
                                      color: context.textColor,
                                    ),
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12.h,
                                  ),
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
                              ),
                            ),
                            if (_tierControllers.length > 1)
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 20.sp,
                                ),
                                onPressed: () => _removeTier(i),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                          ],
                        );
                      }),
                      TextButton.icon(
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: mainColor,
                          size: 20.sp,
                        ),
                        label: Text(
                          'เพิ่มขั้น',
                          style: styles(color: mainColor, fontSize: 14.sp),
                        ),
                        onPressed: () {
                          final lastTo =
                              int.tryParse(
                                _tierControllers.last['qtyTo']?.text ?? '5',
                              ) ??
                              5;
                          if (lastTo == 5) {
                            _tierControllers.last['qtyTo']?.text = '5';
                          }
                          setState(
                            () => _addTier(
                              qtyFrom:
                                  (int.tryParse(
                                        _tierControllers.last['qtyTo']?.text ??
                                            '5',
                                      ) ??
                                      5) +
                                  1,
                              qtyTo: 5,
                              fee: 0,
                            ),
                          );
                        },
                      ),

                      SizedBox(height: 8.h),
                      Text(
                        'เกินจากขั้นสุดท้าย',
                        style: styles(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _extraBaseController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: styles(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w400,
                                color: context.textColor,
                              ),
                              decoration: InputDecoration(
                                label: Text(
                                  'ประกันค่าขนส่ง',
                                  style: styles(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w400,
                                    color: context.textColor,
                                  ),
                                ),
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
                                isDense: true,
                              ),
                            ),
                          ),

                          SizedBox(width: 20.w),
                          Expanded(
                            child: TextField(
                              controller: _extraPerUnitController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: styles(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w400,
                                color: context.textColor,
                              ),
                              decoration: InputDecoration(
                                label: Text(
                                  'ค่าส่งเกินขั้นสุดท้าย',
                                  style: styles(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w400,
                                    color: context.textColor,
                                  ),
                                ),

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
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      TextField(
                        controller: _shippingNoteController,
                        decoration: InputDecoration(
                          labelText: 'หมายเหตุการส่ง',
                          hintText: 'เช่น Kerry 1-3 วันทำการ',
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
                      ),
                    ],

                    ListTile(
                      title: Text(
                        'วันที่เพิ่มสินค้า',
                        style: styles(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w400,
                          color: context.textColor,
                        ),
                      ),
                      subtitle: Text(
                        _scheduleDate != null
                            ? DateFormat('dd/MM/yyyy').format(_scheduleDate!)
                            : 'Not set',
                        style: styles(
                          fontSize: 11.sp,
                          color: context.textColor,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _scheduleDate ?? DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime(5000),
                        );
                        if (date != null) setState(() => _scheduleDate = date);
                      },
                    ),

                    if (showSaveButton)
                      Padding(
                        padding: EdgeInsets.all(20.h),
                        child: SizedBox(
                          width: double.infinity,
                          child: ButtonWidget(
                            label: 'Save Product',
                            style: styles(color: Colors.white),
                            icon: Icons.save_as_rounded,
                            press: () async {
                              if (_formKey.currentState!.validate()) {
                                try {
                                  if (_image.isNotEmpty) {
                                    EasyLoading.show(
                                      status: 'Uploading Images...',
                                    );
                                    List<String> uploadedUrls = [];

                                    for (int i = 0; i < _image.length; i++) {
                                      try {
                                        final img = _image[i];
                                        Reference ref = storage
                                            .ref()
                                            .child('productImage')
                                            .child(const Uuid().v4());
                                        UploadTask task = ref.putFile(img);
                                        TaskSnapshot snapshot = await task;
                                        String url = await snapshot.ref
                                            .getDownloadURL();
                                        uploadedUrls.add(url);
                                      } catch (uploadError) {
                                        Fluttertoast.showToast(
                                          msg: 'Upload รูปที่ $i ล้มเหลว',
                                          backgroundColor: Colors.red,
                                        );
                                      }
                                    }

                                    if (uploadedUrls.isNotEmpty) {
                                      _imageUrlList.addAll(uploadedUrls);
                                      provider.getFormData(
                                        imageUrlList: _imageUrlList,
                                      );
                                      setState(() {
                                        _image = [];
                                      });
                                    }
                                    EasyLoading.dismiss();
                                  }

                                  if (!context.mounted) return;
                                  if (_scannedBarcode != null) {
                                    provider.getFormData(
                                      barcode: _scannedBarcode,
                                      package: _selectedPackage == 'อื่นๆ'
                                          ? _customPackageController.text.trim()
                                          : _selectedPackage,
                                      packageQty:
                                          int.tryParse(
                                            _packageQtyController.text.trim(),
                                          ) ??
                                          1,
                                      unit: _selectedUnit == 'อื่นๆ'
                                          ? _customUnitController.text.trim()
                                          : _selectedUnit,
                                      unitSize:
                                          double.tryParse(
                                            _unitSizeController.text.trim(),
                                          ) ??
                                          0.0,
                                      notify: false,
                                    );
                                  }
                                  provider.getFormData(
                                    saleMode: _saleMode,
                                    shippingTiers: _saleMode == 'ecommerce'
                                        ? _tierControllers
                                              .map(
                                                (tier) => {
                                                  'qtyFrom':
                                                      int.tryParse(
                                                        tier['qtyFrom']?.text
                                                                .trim() ??
                                                            '1',
                                                      ) ??
                                                      1,
                                                  'qtyTo':
                                                      int.tryParse(
                                                        tier['qtyTo']?.text
                                                                .trim() ??
                                                            '5',
                                                      ) ??
                                                      5,
                                                  'fee':
                                                      double.tryParse(
                                                        tier['fee']?.text
                                                                .trim() ??
                                                            '0',
                                                      ) ??
                                                      0.0,
                                                },
                                              )
                                              .toList()
                                        : [],
                                    shippingExtraBase: _saleMode == 'ecommerce'
                                        ? (double.tryParse(
                                                _extraBaseController.text
                                                    .trim(),
                                              ) ??
                                              0.0)
                                        : 0.0,
                                    shippingExtraPerUnit:
                                        _saleMode == 'ecommerce'
                                        ? (double.tryParse(
                                                _extraPerUnitController.text
                                                    .trim(),
                                              ) ??
                                              0.0)
                                        : 0.0,
                                    shippingNote: _saleMode == 'ecommerce'
                                        ? _shippingNoteController.text.trim()
                                        : '',
                                  );
                                  provider.getFormData(
                                    shippingCarrier: _saleMode == 'ecommerce'
                                        ? (_defaultCarrier == 'อื่นๆ'
                                              ? _customCarrierController.text
                                                    .trim()
                                              : _defaultCarrier)
                                        : '',
                                    notify: false,
                                  );
                                  final barcodeToSave = _scannedBarcode;
                                  await provider.saveProduct(context);

                                  if (barcodeToSave != null &&
                                      barcodeToSave.isNotEmpty) {
                                    try {
                                      final masterRef = firestore
                                          .collection('products_master')
                                          .doc(barcodeToSave);
                                      final masterDoc = await masterRef.get();
                                      if (!masterDoc.exists) {
                                        await masterRef.set({
                                          'barcode': barcodeToSave,
                                          'proName':
                                              provider
                                                  .productData['productName'] ??
                                              '',
                                          'description':
                                              provider
                                                  .productData['description'] ??
                                              '',
                                          'type':
                                              provider.productData['type'] ??
                                              '',
                                          'imageUrl':
                                              provider
                                                  .productData['imageUrlList'] ??
                                              [],
                                          'package': _selectedPackage == 'อื่นๆ'
                                              ? _customPackageController.text
                                                    .trim()
                                              : _selectedPackage,
                                          'packageQty':
                                              int.tryParse(
                                                _packageQtyController.text
                                                    .trim(),
                                              ) ??
                                              1,
                                          'unit': _selectedUnit == 'อื่นๆ'
                                              ? _customUnitController.text
                                                    .trim()
                                              : _selectedUnit,
                                          'unitSize':
                                              double.tryParse(
                                                _unitSizeController.text.trim(),
                                              ) ??
                                              0.0,
                                          'contributorVendorId':
                                              auth.currentUser?.uid,
                                          'contributorCount': 1,
                                          'createdAt':
                                              FieldValue.serverTimestamp(),
                                          'updatedAt':
                                              FieldValue.serverTimestamp(),
                                        });
                                      } else {
                                        await masterRef.update({
                                          'contributorCount':
                                              FieldValue.increment(1),
                                          'updatedAt':
                                              FieldValue.serverTimestamp(),
                                        });
                                      }
                                    } catch (e) {
                                      debugPrint(
                                        'Failed to update products_master: $e',
                                      );
                                    }
                                  }
                                } catch (e) {
                                  Fluttertoast.showToast(
                                    msg: e.toString(),
                                    backgroundColor: Colors.red,
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    if (!showSaveButton)
                      Padding(
                        padding: EdgeInsets.all(20.h),
                        child: Card(
                          color: Colors.orange.shade50,
                          child: Padding(
                            padding: EdgeInsets.all(16.h),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.warning,
                                  color: Colors.orange,
                                  size: 40.r,
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  isFormValid
                                      ? 'กรุณาเลือกอย่างน้อย 1 รูปภาพ'
                                      : 'กรุณากรอกข้อมูลให้ครบถ้วนและเลือกอย่างน้อย 1 รูปภาพ',
                                  style: styles(
                                    fontSize: 14.sp,
                                    color: Colors.orange.shade800,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _getGroupIcon(String type) {
    switch (type) {
      case 'free':
        return Icons.free_breakfast;
      case 'singleSelect':
        return Icons.radio_button_checked;
      case 'multiSelect':
        return Icons.check_box;
      case 'size':
        return Icons.straighten;
      default:
        return Icons.menu;
    }
  }

  Color _getGroupColor(String type) {
    switch (type) {
      case 'free':
        return Colors.green;
      case 'singleSelect':
        return Colors.blue;
      case 'multiSelect':
        return Colors.orange;
      case 'size':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Future<dynamic> chooseOption(BuildContext context) {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Choose option',
            style: GoogleFonts.righteous(
              fontWeight: FontWeight.w500,
              color: Colors.yellow.shade900,
            ),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                InkWell(
                  onTap: () {
                    choosCamera();
                    Navigator.pop(context);
                  },
                  splashColor: Colors.yellow.shade900,
                  child: Row(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(8.0.w),
                        child: Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.yellow.shade900,
                        ),
                      ),
                      Text(
                        'Camera',
                        style: GoogleFonts.righteous(
                          fontWeight: FontWeight.w500,
                          color: Colors.cyan.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    choosGallery();
                    Navigator.pop(context);
                  },
                  splashColor: Colors.yellow.shade900,
                  child: Row(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(8.0.w),
                        child: Icon(
                          Icons.image_outlined,
                          color: Colors.green.shade900,
                        ),
                      ),
                      Text(
                        'Gallery',
                        style: GoogleFonts.righteous(
                          fontWeight: FontWeight.w500,
                          color: Colors.cyan.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  splashColor: Colors.yellow.shade900,
                  child: Row(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(8.0.w),
                        child: const Icon(
                          Icons.remove_circle,
                          color: Colors.red,
                        ),
                      ),
                      Text(
                        'Cancel',
                        style: GoogleFonts.righteous(
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

  Future<void> _saveCarrier() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final carrierToSave = _defaultCarrier == 'อื่นๆ'
        ? _customCarrierController.text.trim()
        : _defaultCarrier;
    if (carrierToSave.isEmpty) return;
    try {
      await _firestore.collection('vendors').doc(uid).update({
        'defaultCarrier': carrierToSave,
        'customCarrier': _defaultCarrier == 'อื่นๆ'
            ? _customCarrierController.text.trim()
            : '',
      });
    } catch (e) {
      Fluttertoast.showToast(msg: 'บันทึกผิดพลาด: $e');
    }
  }
}
