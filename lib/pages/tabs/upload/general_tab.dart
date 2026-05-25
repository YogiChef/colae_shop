// ignore_for_file: depend_on_referenced_packages, no_leading_underscores_for_local_identifiers

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:colae_shop/pages/tabs/upload/type.dart';
import 'package:colae_shop/providers/product_provider.dart';
import 'package:colae_shop/services/sevice.dart';
import 'package:colae_shop/widgets/button_widget.dart';
import 'package:colae_shop/widgets/input_textfield.dart';

class GeneralTab extends StatefulWidget {
  const GeneralTab({super.key});

  @override
  State<GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<GeneralTab> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final List<String> _categoryList = [];
  List<File> _image = [];
  final List<String> _imageUrlList = [];
  final ImagePicker picker = ImagePicker();
  bool? _chargeShipping = false;
  final TextEditingController _shippingController = TextEditingController();

  Future<void> getType() {
    return firestore.collection('type').get().then((QuerySnapshot snapshot) {
      final types = snapshot.docs
          .map((doc) => doc['typename'] as String)
          .toList();
      if (mounted) setState(() => _categoryList.addAll(types));
    });
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
                initialValue: selectedType,
                decoration: const InputDecoration(
                  labelText: 'ประเภทกลุ่ม',
                  border: OutlineInputBorder(),
                ),
                items: OptionGroupType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.toString().split('.').last.toUpperCase()),
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
              child: const Text('ยกเลิก'),
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
              child: const Text('เพิ่ม'),
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
              decoration: const InputDecoration(
                labelText: 'ชื่อตัวเลือก (e.g., ชีส)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceController,
              keyboardType: isFree ? TextInputType.none : TextInputType.number,
              readOnly: isFree,
              decoration: InputDecoration(
                labelText: isFree ? 'ฟรี (ราคา 0)' : 'ราคาเพิ่ม (e.g., 20)',
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
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    getType();
    super.initState();
  }

  String formatedDate(DateTime date) {
    final outPutDateFormate = DateFormat('dd/MM/yyyy');
    final outPutDate = outPutDateFormate.format(date);
    return outPutDate;
  }

  @override
  Widget build(BuildContext context) {
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
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(8.0.h),
                    child: GridView.builder(
                      shrinkWrap: true,
                      itemCount: _image.length + 1,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.5,
                            crossAxisSpacing: 8,
                          ),
                      itemBuilder: (context, index) {
                        return index == 0
                            ? Material(
                                elevation: 10,
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
                                          color: Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        'Choose Images',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.righteous(
                                          fontSize: 14.sp,
                                          color: Colors.grey,
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
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    padding: EdgeInsets.only(
                      left: 20.w,
                      right: 20.w,
                      bottom: 10.w,
                    ),
                    icon: const Icon(Icons.keyboard_arrow_down),
                    decoration: InputDecoration(
                      prefixIcon: IconButton(
                        icon: const Icon(Icons.inventory),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const TypeTab(),
                            ),
                          );
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
                    ),
                    hint: Text('Select Type', style: styles(fontSize: 12.sp)),
                    items: _categoryList.map<DropdownMenuItem<String>>((e) {
                      return DropdownMenuItem(value: e, child: Text(e));
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        provider.getFormData(type: value);
                      }
                    },
                    validator: (value) =>
                        value == null ? 'กรุณาเลือกประเภทสินค้า' : null,
                  ),
                  InputTextfield(
                    textInputType: TextInputType.text,
                    prefixIcon: const Icon(Icons.drive_file_rename_outline),
                    hintText: 'Product Name',
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
                    hintText: 'Product Price',
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
                  InputTextfield(
                    textInputType: TextInputType.number,
                    prefixIcon: const Icon(Icons.qr_code),
                    hintText: 'Product Quantity',
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
                      provider.getFormData();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 0,
                    ),
                    child: TextFormField(
                      keyboardType: TextInputType.text,
                      maxLength: 400,
                      maxLines: 3,
                      validator: (value) {
                        if (value!.isEmpty) {
                          return 'Please enter product description';
                        } else {
                          return null;
                        }
                      },
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        labelText: 'Product Description',
                        labelStyle: styles(color: Colors.black54),
                        errorBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.red, width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.yellow.shade900,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        provider.getFormData(description: value);
                      },
                    ),
                  ),
                  CheckboxListTile(
                    activeColor: Colors.yellow.shade900,
                    title: Text(
                      'Charge Shipping',
                      style: GoogleFonts.righteous(
                        fontSize: 14.sp,
                        letterSpacing: 1,
                        color: Colors.black54,
                      ),
                    ),
                    value: _chargeShipping,
                    onChanged: (value) {
                      setState(() {
                        _chargeShipping = value;
                      });
                      provider.getFormData(chargeShipping: _chargeShipping);
                      if (value == false) {
                        _shippingController.clear();
                        provider.getFormData(shippingCharge: 0.0);
                      }
                    },
                  ),
                  if (_chargeShipping == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextFormField(
                        controller: _shippingController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            CupertinoIcons.money_dollar_circle,
                          ),
                          hintText: 'Shipping Charge',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.yellow.shade900,
                              width: 2,
                            ),
                          ),
                          errorBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.red, width: 2),
                          ),
                          suffixText: '฿',
                        ),
                        validator: (value) {
                          if (value!.isEmpty) {
                            return 'Please enter shipping charge';
                          }
                          final charge = double.tryParse(value);
                          if (charge == null || charge <= 0) {
                            return 'Shipping charge must be greater than 0';
                          }
                          if (charge > 5) {
                            return 'Shipping charge must not exceed 5';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          final newCharge = double.tryParse(value);
                          if (newCharge != null && newCharge > 5.0) {
                            showDialog(
                              context: context,
                              builder: (BuildContext ctx) => AlertDialog(
                                title: Icon(
                                  Icons.warning,
                                  color: Colors.orange,
                                  size: 50.r,
                                ),
                                content: const Text(
                                  'ไม่สามารถคิดค่าส่งเกิน 5 บาท',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('ตกลง'),
                                  ),
                                ],
                              ),
                            );
                            _shippingController.text = '5';
                            provider.getFormData(shippingCharge: 5.0);
                          } else if (newCharge != null) {
                            provider.getFormData(shippingCharge: newCharge);
                          }
                        },
                      ),
                    ),
                  ExpansionTile(
                    title: const Text('ตัวเลือกเมนู'),
                    subtitle: Text('${provider.optionGroups.length} กลุ่ม'),
                    leading: const Icon(Icons.menu_book),
                    children: [
                      if (provider.optionGroups.isEmpty)
                        ListTile(
                          title: const Text('ไม่มีกลุ่มตัวเลือก'),
                          subtitle: const Text('กด "เพิ่ม" เพื่อสร้าง'),
                          trailing: IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: _addGroupDialog,
                          ),
                        )
                      else
                        ...provider.optionGroups.asMap().entries.map((entry) {
                          int groupIndex = entry.key;
                          Map<String, dynamic> group = entry.value;
                          final groupType = group['type'] as String;
                          final groupName =
                              group['name'] ?? groupType.toUpperCase();
                          final options =
                              group['options'] as List<Map<String, dynamic>>;
                          return ExpansionTile(
                            key: ValueKey(groupIndex),
                            title: Text(groupName),
                            subtitle: Text(
                              'ประเภท: $groupType • ${options.length} ตัวเลือก',
                            ),
                            leading: Icon(
                              _getGroupIcon(groupType),
                              color: _getGroupColor(groupType),
                            ),
                            children: [
                              if (options.isEmpty)
                                ListTile(
                                  title: const Text('ไม่มีตัวเลือก'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () =>
                                        _addOptionToGroupDialog(groupIndex),
                                  ),
                                )
                              else
                                ...options.asMap().entries.map((optEntry) {
                                  int optIndex = optEntry.key;
                                  Map<String, dynamic> option = optEntry.value;
                                  return ListTile(
                                    title: Text(option['name']),
                                    subtitle: Text('ราคา: ฿${option['price']}'),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      onPressed: () {
                                        provider.removeOptionFromGroup(
                                          groupIndex,
                                          optIndex,
                                        );
                                      },
                                    ),
                                  );
                                }),
                              ListTile(
                                title: const Text('เพิ่มตัวเลือกในกลุ่มนี้'),
                                trailing: const Icon(Icons.add),
                                onTap: () =>
                                    _addOptionToGroupDialog(groupIndex),
                              ),
                              ListTile(
                                title: const Text('ลบกลุ่มนี้'),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_forever,
                                    color: Colors.red,
                                  ),
                                  onPressed: () {
                                    provider.removeOptionGroup(groupIndex);
                                    Fluttertoast.showToast(
                                      msg: 'ลบกลุ่มสำเร็จ!',
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        }),
                      ListTile(
                        title: const Text('เพิ่มกลุ่มตัวเลือก'),
                        trailing: const Icon(Icons.add),
                        onTap: _addGroupDialog,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextButton(
                          onPressed: () {
                            showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(1900),
                              lastDate: DateTime(5000),
                            ).then((value) {
                              if (value != null) {
                                provider.getFormData(date: value);
                              }
                            });
                          },
                          child: Text(
                            'Schedule',
                            style: styles(
                              color: mainColor,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      if (provider.productData['date'] != null)
                        Text(
                          formatedDate(provider.productData['date']),
                          style: styles(color: Colors.black54, fontSize: 14),
                        ),
                    ],
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
                                await provider.saveProduct(context);
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
}
