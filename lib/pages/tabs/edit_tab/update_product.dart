// ignore_for_file: depend_on_referenced_packages, use_build_context_synchronously, deprecated_member_use, unnecessary_underscores

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:colae_shop/providers/product_provider.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/widgets/button_widget.dart';
import 'package:colae_shop/widgets/input_textfield.dart';

class UpdateProductPage extends StatefulWidget {
  final DocumentSnapshot productData;
  const UpdateProductPage({super.key, required this.productData});

  @override
  State<UpdateProductPage> createState() => _UpdateProductPageState();
}

class _UpdateProductPageState extends State<UpdateProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _proNameCtl = TextEditingController();
  final _qtyNameCtl = TextEditingController();
  final _proPriceCtl = TextEditingController();
  final _proDesCtl = TextEditingController();
  final _categoryCtl = TextEditingController();
  final _shippingChargeCtl = TextEditingController();

  final ImagePicker picker = ImagePicker();
  final List<File> _newImages = [];
  List<String> _imageUrlList = [];

  bool _chargeShipping = false;
  DateTime? _scheduleDate;
  final List<String> _categoryList = [];
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    final data = widget.productData.data() as Map<String, dynamic>? ?? {};
    _proNameCtl.text = data['proName']?.toString() ?? '';
    _qtyNameCtl.text = (data['pqty'] ?? 0).toString();
    _proPriceCtl.text = (data['price'] ?? 0).toString();
    _proDesCtl.text = data['description']?.toString() ?? '';
    final cat = data['type']?.toString() ?? '';
    _selectedCategory = cat.isNotEmpty ? cat : null;
    _categoryCtl.text = cat;
    _chargeShipping = data['chargeShipping'] ?? false;
    _shippingChargeCtl.text = (data['shippingCharge'] ?? 0).toString();
    final dateValue = data['date'];
    _scheduleDate = dateValue is Timestamp
        ? dateValue.toDate()
        : dateValue as DateTime?;
    _imageUrlList = List<String>.from(data['imageUrl'] ?? []);

    _loadCategories();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<ProductProvider>(
          context,
          listen: false,
        ).loadFromSnapshot(widget.productData);
      }
    });
  }

  Future<void> _loadCategories() async {
    try {
      final snapshot = await firestore.collection('type').get();
      _categoryList.addAll(snapshot.docs.map((e) => e['typename'].toString()));
      if (mounted) setState(() {});
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString(), backgroundColor: Colors.red);
    }
  }

  @override
  void dispose() {
    _proNameCtl.dispose();
    _qtyNameCtl.dispose();
    _proPriceCtl.dispose();
    _proDesCtl.dispose();
    _categoryCtl.dispose();
    _shippingChargeCtl.dispose();
    super.dispose();
  }

  Future<List<String>> _uploadNewImages() async {
    if (_newImages.isEmpty) return [];
    final results = await Future.wait(
      _newImages.map((img) async {
        try {
          final ref = storage
              .ref()
              .child('productImage')
              .child(const Uuid().v4().toString());
          final snapshot = await ref.putFile(img);
          return await snapshot.ref.getDownloadURL();
        } catch (e) {
          Fluttertoast.showToast(msg: 'Upload image failed: $e');
          return null;
        }
      }),
    );
    return results.whereType<String>().toList();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate() || !mounted) return;

    EasyLoading.show(status: 'กำลังแก้ไขข้อมูล...');

    try {
      final newImageUrls = await _uploadNewImages();
      if (newImageUrls.isNotEmpty) _imageUrlList.addAll(newImageUrls);

      final provider = Provider.of<ProductProvider>(context, listen: false);
      final qty = int.tryParse(_qtyNameCtl.text) ?? 0;
      final price = double.tryParse(_proPriceCtl.text) ?? 0.0;
      final shipping = _chargeShipping
          ? double.tryParse(_shippingChargeCtl.text) ?? 0.0
          : 0.0;

      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}

      await firestore.collection('products').doc(widget.productData.id).update({
        'proName': _proNameCtl.text.trim(),
        'pqty': qty,
        'price': price,
        'description': _proDesCtl.text.trim(),
        'type': _categoryCtl.text.trim(),
        'chargeShipping': _chargeShipping,
        'shippingCharge': shipping,
        'date': _scheduleDate != null
            ? Timestamp.fromDate(_scheduleDate!)
            : null,
        'imageUrl': _imageUrlList,
        'optionGroups': provider.optionGroups,
      });

      Fluttertoast.showToast(msg: 'อัปเดตสินค้าสำเร็จ!');
      EasyLoading.dismiss();

      if (mounted) {
        Navigator.pop(context);
        provider.clearData();
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'อัปเดตผิดพลาด: $e',
          backgroundColor: Colors.red,
        );
        EasyLoading.dismiss();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20.r,
              backgroundColor: _imageUrlList.isNotEmpty ? null : Colors.grey,
              backgroundImage: _imageUrlList.isNotEmpty
                  ? NetworkImage(_imageUrlList[0])
                  : null,
              child: _imageUrlList.isNotEmpty
                  ? null
                  : const Icon(Icons.image, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.productData.get('proName')?.toString() ??
                    'Unnamed Product',
                style: styles(fontSize: 13.sp, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
          child: Column(
            children: [
              SizedBox(
                height: 100.h,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _imageUrlList.length + _newImages.length + 1,
                  itemBuilder: (context, index) {
                    if (index < _imageUrlList.length) {
                      return Stack(
                        children: [
                          Image.network(
                            _imageUrlList[index],
                            width: 120.w,
                            height: 90.h,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 120.w,
                              height: 90.h,
                              color: Colors.grey,
                              child: const Icon(Icons.error),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () =>
                                  setState(() => _imageUrlList.removeAt(index)),
                            ),
                          ),
                        ],
                      );
                    } else if (index <
                        _imageUrlList.length + _newImages.length) {
                      final newIdx = index - _imageUrlList.length;
                      return Stack(
                        children: [
                          Image.file(
                            _newImages[newIdx],
                            width: 80.w,
                            height: 80.h,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () =>
                                  setState(() => _newImages.removeAt(newIdx)),
                            ),
                          ),
                        ],
                      );
                    } else {
                      return IconButton(
                        icon: const Icon(Icons.add_photo_alternate),
                        onPressed: () async {
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (picked != null) {
                            setState(() => _newImages.add(File(picked.path)));
                          }
                        },
                      );
                    }
                  },
                ),
              ),

              DropdownButtonFormField<String>(
                value: _selectedCategory,
                isExpanded: true,
                hint: Text(
                  'เลือกประเภทสินค้า',
                  style: styles(fontSize: 14.sp, color: Colors.black45),
                ),
                items: _categoryList
                    .map(
                      (cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(cat, style: styles(fontSize: 14.sp)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null && mounted) {
                    setState(() {
                      _selectedCategory = value;
                      _categoryCtl.text = value;
                    });
                    Provider.of<ProductProvider>(
                      context,
                      listen: false,
                    ).getFormData(type: value);
                  }
                },
                validator: (v) => v == null ? 'กรุณาเลือกประเภทสินค้า' : null,
              ),
              SizedBox(height: 16.h),

              // ชื่อสินค้า, จำนวน, ราคา, รายละเอียด
              InputTextfield(
                controller: _proNameCtl,
                textInputType: TextInputType.text,
                prefixIcon: const Icon(Icons.drive_file_rename_outline),
                hintText: 'Product Name',
                label: const Text('Product Name'),
                validator: (value) =>
                    value!.isEmpty ? 'กรุณากรอกชื่อสินค้า' : null,
              ),
              InputTextfield(
                controller: _qtyNameCtl,
                textInputType: TextInputType.number,
                prefixIcon: const Icon(
                  Icons.production_quantity_limits_outlined,
                ),
                hintText: 'Quantity',
                label: const Text('Quantity'),
                validator: (value) {
                  final qty = int.tryParse(value ?? '');
                  return qty == null || qty <= 0 ? 'จำนวนต้องมากกว่า 0' : null;
                },
              ),
              InputTextfield(
                controller: _proPriceCtl,
                textInputType: TextInputType.number,
                prefixIcon: const Icon(Icons.money_sharp),
                hintText: 'Price',
                label: const Text('Price'),
                validator: (value) {
                  final price = double.tryParse(value ?? '');
                  return price == null || price <= 0
                      ? 'ราคาต้องมากกว่า 0'
                      : null;
                },
              ),
              InputTextfield(
                controller: _proDesCtl,
                textInputType: TextInputType.multiline,
                maxLines: 3,
                prefixIcon: const Icon(Icons.description_outlined),
                hintText: 'Description',
                label: const Text('Description'),
                validator: (value) =>
                    value!.isEmpty ? 'กรุณากรอกรายละเอียด' : null,
              ),

              Consumer<ProductProvider>(
                builder: (context, provider, child) {
                  final groups = provider.optionGroups;
                  return ExpansionTile(
                    leading: const Icon(Icons.menu_book),
                    title: const Text('ตัวเลือกเมนู'),
                    subtitle: Text(
                      groups.isEmpty ? '' : '${groups.length} กลุ่ม',
                    ),
                    children: [
                      ...groups.asMap().entries.map((entry) {
                        final groupIndex = entry.key;
                        final group = entry.value;
                        final groupType = group['type'] as String;
                        final groupTypeEnum = OptionGroupType.values.firstWhere(
                          (e) => e.name == groupType,
                          orElse: () => OptionGroupType.free,
                        );
                        final groupName =
                            group['name'] ?? groupType.toUpperCase();
                        final options = List<Map<String, dynamic>>.from(
                          group['options'] ?? [],
                        );

                        return ExpansionTile(
                          key: ValueKey(groupIndex),
                          leading: Icon(
                            _getGroupIcon(groupType),
                            color: _getGroupColor(groupType),
                          ),
                          title: Text(groupName),
                          subtitle: Text(
                            '${groupTypeEnum.label} • ${options.length} ตัวเลือก',
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
                              final optIndex = optEntry.key;
                              final opt = optEntry.value;
                              return ListTile(
                                dense: true,
                                title: Text(opt['name'] ?? ''),
                                subtitle: Text(
                                  opt['price'] == 0
                                      ? 'ฟรี'
                                      : '+฿${opt['price']}',
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
                              title: const Text('เพิ่มตัวเลือก'),
                              onTap: () => _addOptionToGroupDialog(groupIndex),
                            ),
                          ],
                        );
                      }),
                      ListTile(
                        leading: const Icon(
                          Icons.add,
                          color: Colors.deepOrange,
                        ),
                        title: const Text('เพิ่มกลุ่มตัวเลือกใหม่'),
                        onTap: _addGroupDialog,
                      ),
                    ],
                  );
                },
              ),

              CheckboxListTile(
                title: Text(
                  'ค่าจัดส่ง',
                  style: styles(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w400,
                    color: Colors.black54,
                  ),
                ),
                value: _chargeShipping,
                onChanged: (value) =>
                    setState(() => _chargeShipping = value ?? false),
              ),
              if (_chargeShipping)
                InputTextfield(
                  controller: _shippingChargeCtl,
                  textInputType: TextInputType.number,
                  prefixIcon: const Icon(CupertinoIcons.money_dollar_circle),
                  hintText: 'Shipping Charge (max 5)',
                  label: const Text('Shipping Charge'),
                  validator: (value) {
                    final charge = double.tryParse(value ?? '');
                    if (charge == null || charge <= 0) {
                      return 'ค่าส่งต้องมากกว่า 0';
                    }
                    if (charge > 5) return 'ค่าส่งไม่เกิน 5';
                    return null;
                  },
                ),

              ListTile(
                title: Text(
                  'วันที่เพิ่มสินค้า',
                  style: styles(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w400,
                    color: Colors.black54,
                  ),
                ),
                subtitle: Text(
                  _scheduleDate != null
                      ? DateFormat('dd/MM/yyyy').format(_scheduleDate!)
                      : 'Not set',
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

              SizedBox(height: 80.h),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            left: 24.w,
            right: 24.w,
            top: 12.w,
            bottom: MediaQuery.of(context).viewPadding.bottom + 12.h,
          ),
          child: ButtonWidget(
            // แก้จาก BottonWidget
            label: 'อัปเดทสินค้า',
            style: styles(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
            ),
            icon: Icons.update,
            press: () async => await _saveProduct(),
          ),
        ),
      ),
    );
  }

  void _addGroupDialog() {
    final provider = Provider.of<ProductProvider>(context, listen: false);
    final groupNameController = TextEditingController();
    OptionGroupType? selectedType;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('เพิ่มกลุ่มตัวเลือก'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: groupNameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อกลุ่ม',
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
                onChanged: (value) =>
                    setDialogState(() => selectedType = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () {
                if (selectedType != null) {
                  provider.addOptionGroup(
                    selectedType!,
                    groupName: groupNameController.text.trim().isEmpty
                        ? null
                        : groupNameController.text.trim(),
                  );
                  Navigator.pop(dialogContext);
                  Fluttertoast.showToast(msg: 'เพิ่มกลุ่มสำเร็จ!');
                } else {
                  Fluttertoast.showToast(
                    msg: 'กรุณาเลือกประเภทกลุ่ม',
                    backgroundColor: Colors.red,
                  );
                }
              },
              child: const Text('เพิ่ม'),
            ),
          ],
        ),
      ),
    );
  }

  void _addOptionToGroupDialog(int groupIndex) {
    final provider = Provider.of<ProductProvider>(context, listen: false);
    final nameController = TextEditingController();
    final priceController = TextEditingController();

    final groupType = provider.optionGroups[groupIndex]['type'] as String;
    final isFree = groupType == 'free';
    if (isFree) priceController.text = '0';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'เพิ่มตัวเลือกในกลุ่ม: ${provider.optionGroups[groupIndex]['name'] ?? provider.optionGroups[groupIndex]['type']}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'ชื่อตัวเลือก',
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
                border: const OutlineInputBorder(),
                suffixText: isFree ? '฿0' : '฿',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
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
                Navigator.pop(dialogContext);
                Fluttertoast.showToast(msg: 'เพิ่มตัวเลือกสำเร็จ!');
              } else {
                Fluttertoast.showToast(
                  msg: 'กรุณากรอกชื่อตัวเลือก',
                  backgroundColor: Colors.red,
                );
              }
            },
            child: const Text('เพิ่ม'),
          ),
        ],
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
}
