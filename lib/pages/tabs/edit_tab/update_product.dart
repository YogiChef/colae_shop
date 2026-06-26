// ignore_for_file: depend_on_referenced_packages, use_build_context_synchronously, deprecated_member_use, unnecessary_underscores

import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  final ImagePicker picker = ImagePicker();
  final List<File> _newImages = [];
  List<String> _imageUrlList = [];

  DateTime? _scheduleDate;
  final List<String> _categoryList = [];
  String? _selectedCategory;
  String _saleMode = 'delivery';
  bool _trackStock = true;
  final List<Map<String, TextEditingController>> _tierControllers = [];
  final TextEditingController _extraBaseController = TextEditingController(
    text: '0',
  );
  final TextEditingController _extraPerUnitController = TextEditingController(
    text: '0',
  );
  final TextEditingController _shippingNoteController = TextEditingController();

  void _addTier({int qtyFrom = 1, int qtyTo = 5, double fee = 0}) {
    _tierControllers.add({
      'qtyFrom': TextEditingController(text: qtyFrom.toString()),
      'qtyTo': TextEditingController(text: qtyTo.toString()),
      'fee': TextEditingController(text: fee.toStringAsFixed(0)),
    });
  }

  void _removeTier(int index) {
    final tier = _tierControllers[index];
    tier['qtyFrom']?.dispose();
    tier['qtyTo']?.dispose();
    tier['fee']?.dispose();
    setState(() => _tierControllers.removeAt(index));
  }

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
    final dateValue = data['date'];
    _scheduleDate = dateValue is Timestamp
        ? dateValue.toDate()
        : dateValue as DateTime?;
    _imageUrlList = List<String>.from(data['imageUrl'] ?? []);
    _saleMode = data['saleMode']?.toString() ?? 'delivery';
    _trackStock = data['trackStock'] as bool? ?? true;
    final tiers = data['shippingTiers'] as List?;
    if (tiers != null && tiers.isNotEmpty) {
      for (final tier in tiers) {
        final m = Map<String, dynamic>.from(tier as Map);
        _addTier(
          qtyFrom: (m['qtyFrom'] as num?)?.toInt() ?? 1,
          qtyTo: (m['qtyTo'] as num?)?.toInt() ?? 5,
          fee: (m['fee'] as num?)?.toDouble() ?? 0.0,
        );
      }
    } else if (data['ecommerceShippingFee'] != null) {
      _addTier(
        qtyFrom: 1,
        qtyTo: 5,
        fee: (data['ecommerceShippingFee'] as num).toDouble(),
      );
    } else {
      _addTier(qtyTo: 5);
    }
    _extraBaseController.text =
        ((data['shippingExtraBase'] as num?)?.toStringAsFixed(0)) ?? '0';
    _extraPerUnitController.text =
        ((data['shippingExtraPerUnit'] as num?)?.toStringAsFixed(0)) ?? '0';
    _shippingNoteController.text = data['shippingNote']?.toString() ?? '';

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
    for (final tier in _tierControllers) {
      tier['qtyFrom']?.dispose();
      tier['qtyTo']?.dispose();
      tier['fee']?.dispose();
    }
    _extraBaseController.dispose();
    _extraPerUnitController.dispose();
    _shippingNoteController.dispose();
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

      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}

      await firestore.collection('products').doc(widget.productData.id).update({
        'proName': _proNameCtl.text.trim(),
        'pqty': _trackStock ? qty : 0,
        'trackStock': _trackStock,
        'price': price,
        'description': _proDesCtl.text.trim(),
        'type': _categoryCtl.text.trim(),
        'date': _scheduleDate != null
            ? Timestamp.fromDate(_scheduleDate!)
            : null,
        'imageUrl': _imageUrlList,
        'optionGroups': provider.optionGroups,
        'saleMode': _saleMode,
        'shippingTiers': _saleMode == 'ecommerce'
            ? _tierControllers
                  .map(
                    (tier) => {
                      'qtyFrom':
                          int.tryParse(tier['qtyFrom']?.text.trim() ?? '1') ??
                          1,
                      'qtyTo':
                          int.tryParse(tier['qtyTo']?.text.trim() ?? '5') ?? 5,
                      'fee':
                          double.tryParse(tier['fee']?.text.trim() ?? '0') ??
                          0.0,
                    },
                  )
                  .toList()
            : [],
        'shippingExtraBase': _saleMode == 'ecommerce'
            ? (double.tryParse(_extraBaseController.text.trim()) ?? 0.0)
            : 0.0,
        'shippingExtraPerUnit': _saleMode == 'ecommerce'
            ? (double.tryParse(_extraPerUnitController.text.trim()) ?? 0.0)
            : 0.0,
        'shippingNote': _saleMode == 'ecommerce'
            ? _shippingNoteController.text.trim()
            : '',
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
        backgroundColor: context.isDark ? Colors.transparent : mainColor,
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
                  ? CachedNetworkImageProvider(_imageUrlList[0])
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
                style: styles(fontSize: 16.sp, color: Colors.white),
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
                          CachedNetworkImage(
                            imageUrl: _imageUrlList[index],
                            width: 120.w,
                            height: 90.h,
                            fit: BoxFit.cover,
                            memCacheWidth: 400,
                            placeholder: (_, __) => Container(
                              width: 120.w,
                              height: 90.h,
                              color: Colors.grey.shade200,
                            ),
                            errorWidget: (_, __, ___) => Container(
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
                  style: styles(fontSize: 14.sp, color: context.textColor),
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
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                ),
                items: _categoryList
                    .map(
                      (cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(
                          cat,
                          style: styles(
                            fontSize: 14.sp,
                            color: context.textColor,
                          ),
                        ),
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

              InputTextfield(
                controller: _proNameCtl,
                textInputType: TextInputType.text,
                prefixIcon: const Icon(Icons.drive_file_rename_outline),
                hintText: 'Product Name',
                label: const Text('Product Name'),
                validator: (value) =>
                    value!.isEmpty ? 'กรุณากรอกชื่อสินค้า' : null,
              ),
              SwitchListTile(
                title: Text(
                  'ตัดสต๊อก',
                  style: styles(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: context.textColor,
                  ),
                ),
                subtitle: Text(
                  _trackStock
                      ? 'จำกัดจำนวน — ตัดสต๊อกอัตโนมัติเมื่อขาย'
                      : 'ไม่จำกัดจำนวน — เหมาะกับอาหาร/บริการ',
                  style: styles(fontSize: 11.sp, color: context.subColor),
                ),
                value: _trackStock,
                onChanged: (val) => setState(() => _trackStock = val),
                activeColor: mainColor,
                contentPadding: EdgeInsets.zero,
              ),
              if (_trackStock)
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
                    return qty == null || qty <= 0
                        ? 'จำนวนต้องมากกว่า 0'
                        : null;
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
                    title: Text(
                      'ตัวเลือกเมนู',
                      style: styles(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: context.textColor,
                      ),
                    ),
                    subtitle: Text(
                      groups.isEmpty ? '' : '${groups.length} กลุ่ม',
                      style: styles(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        color: context.textColor,
                      ),
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
                            '${groupTypeEnum.label} / ${options.length} ตัวเลือก',
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
                                title: Text(
                                  opt['name'] ?? '',
                                  style: styles(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w500,
                                    color: context.textColor,
                                  ),
                                ),
                                subtitle: Text(
                                  opt['price'] == 0
                                      ? 'ฟรี'
                                      : '+฿${opt['price']}',
                                  style: styles(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w500,
                                    color: context.textColor,
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
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w500,
                                  color: context.textColor,
                                ),
                              ),
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
                        title: Text(
                          'เพิ่มกลุ่มตัวเลือกใหม่',
                          style: styles(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            color: context.textColor,
                          ),
                        ),
                        onTap: _addGroupDialog,
                      ),
                    ],
                  );
                },
              ),

              SizedBox(height: 12.h),
              DropdownButtonFormField<String>(
                value: _saleMode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'รูปแบบการขาย',
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
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                  helperText: 'delivery=ส่งใกล้ร้าน, ecommerce=ส่งทั่วประเทศ',
                  helperMaxLines: 2,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'delivery',
                    child: Text('🛵 Delivery', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'ecommerce',
                    child: Text(
                      '📦 Ecommerce',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _saleMode = v ?? 'delivery'),
              ),
              if (_saleMode == 'ecommerce') ...[
                SizedBox(height: 12.h),
                Text(
                  'ค่าส่ง',
                  textAlign: TextAlign.left,
                  style: styles(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: context.textColor,
                  ),
                ),

                SizedBox(height: 8.h),
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
                              horizontal: 8.w,
                              vertical: 8.h,
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
                              horizontal: 8.w,
                              vertical: 8.h,
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
                              horizontal: 8.w,
                              vertical: 8.h,
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
                  icon: Icon(Icons.add_circle_outline, color: mainColor),
                  label: Text('เพิ่มขั้น', style: styles(color: mainColor)),
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
                                  _tierControllers.last['qtyTo']?.text ?? '5',
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
                  style: styles(fontSize: 12.sp, fontWeight: FontWeight.w600),
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
                        color: context.isDark ? Colors.white70 : Colors.grey,
                        width: 1,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
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
                decoration: InputDecoration(
                  labelText: 'ประเภทกลุ่ม',
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
                      color: context.isDark ? Colors.white70 : Colors.grey,
                      width: 1,
                    ),
                  ),
                ),
                items: OptionGroupType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(
                      type.label,
                      style: styles(fontSize: 14.sp, color: context.textColor),
                    ),
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
              decoration: InputDecoration(
                labelText: 'ชื่อตัวเลือก',
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
                    color: context.isDark ? Colors.white70 : Colors.grey,
                    width: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceController,
              keyboardType: isFree ? TextInputType.none : TextInputType.number,
              readOnly: isFree,
              decoration: InputDecoration(
                labelText: isFree ? 'ฟรี' : 'ราคาเพิ่ม',
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
                    color: context.isDark ? Colors.white70 : Colors.grey,
                    width: 1,
                  ),
                ),
                suffixText: isFree ? '฿0' : '฿',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
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
