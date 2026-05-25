import 'package:cloud_firestore/cloud_firestore.dart';

class VendorModel {
  final bool? approved;
  final String vendorId;
  final String bussinessName;
  final String? ownerName; // ← เพิ่ม
  final String city;
  final String country;
  final String address;
  final String zipcode;
  final String email;
  final String image;
  final String? faceImage; // ← เพิ่ม
  final String? idCardImage; // ← เพิ่ม
  final String phone;
  final String category;
  final String state;
  final String taxStatus;
  final String taxNo;
  final String bankName;
  final String bankAccount;
  final String promptPayId;
  final String? qrCodeImage; // ← เพิ่ม
  final String? idNumber; // ← เพิ่ม
  final String? birthDate; // ← เพิ่ม
  final String? cardOwnerName; // ← เพิ่ม
  final Map<String, dynamic>? storeHours;
  final bool temporarilyClosed;
  final GeoPoint? location;
  final num? totalSales;
  final num? pendingFee;
  final Timestamp? nextDueDate;

  VendorModel({
    this.approved,
    required this.vendorId,
    required this.bussinessName,
    this.ownerName,
    required this.city,
    required this.country,
    required this.address,
    required this.zipcode,
    required this.email,
    required this.image,
    this.faceImage,
    this.idCardImage,
    required this.phone,
    required this.category,
    required this.state,
    required this.taxStatus,
    required this.taxNo,
    required this.bankName,
    required this.bankAccount,
    required this.promptPayId,
    this.qrCodeImage,
    this.idNumber,
    this.birthDate,
    this.cardOwnerName,
    this.storeHours,
    this.temporarilyClosed = false,
    this.location,
    this.totalSales,
    this.pendingFee,
    this.nextDueDate,
  });

  factory VendorModel.fromJson(Map<String, Object?> json) {
    bool? approved;
    if (json['approved'] is bool) {
      approved = json['approved'] as bool;
    } else if (json['approved'] is String) {
      approved = json['approved'].toString().toLowerCase() == 'true';
    } else {
      approved = false;
    }

    return VendorModel(
      approved: approved,
      vendorId: json['vendorId'] as String? ?? '',
      bussinessName: json['bussinessName'] as String? ?? 'Unknown',
      ownerName: json['ownerName'] as String?,
      city: json['city'] as String? ?? '',
      country: json['country'] as String? ?? '',
      address: json['address'] as String? ?? '',
      zipcode: json['vzipcode'] as String? ?? '',
      email: json['email'] as String? ?? '',
      image: json['image'] as String? ?? '',
      faceImage: json['faceImage'] as String?,
      idCardImage: json['idCardImage'] as String?,
      phone: json['phone'] as String? ?? '',
      category: json['category'] as String? ?? '',
      state: json['state'] as String? ?? '',
      taxStatus: json['taxStatus'] as String? ?? '',
      taxNo: json['taxNo'] as String? ?? '',
      bankName: json['bankName'] as String? ?? '',
      bankAccount: json['bankAccount'] as String? ?? '',
      promptPayId: json['promptPayId'] as String? ?? '',
      qrCodeImage: json['qrCodeImage'] as String?,
      idNumber: json['idNumber'] as String?,
      birthDate: json['birthDate'] as String?,
      cardOwnerName: json['cardOwnerName'] as String?,
      storeHours: json['storeHours'] as Map<String, dynamic>?,
      temporarilyClosed: json['temporarilyClosed'] as bool? ?? false,
      location: json['location'] as GeoPoint?,
      totalSales: json['totalSales'] as num?,
      pendingFee: json['pendingFee'] as num?,
      nextDueDate: json['nextDueDate'] as Timestamp?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'approved': approved,
      'vendorId': vendorId,
      'bussinessName': bussinessName,
      if (ownerName != null) 'ownerName': ownerName,
      'city': city,
      'country': country,
      'address': address,
      'vzipcode': zipcode,
      'email': email,
      'image': image,
      if (faceImage != null) 'faceImage': faceImage,
      if (idCardImage != null) 'idCardImage': idCardImage,
      'phone': phone,
      'category': category,
      'state': state,
      'taxStatus': taxStatus,
      'taxNo': taxNo,
      'bankName': bankName,
      'bankAccount': bankAccount,
      'promptPayId': promptPayId,
      if (qrCodeImage != null) 'qrCodeImage': qrCodeImage,
      if (idNumber != null) 'idNumber': idNumber,
      if (birthDate != null) 'birthDate': birthDate,
      if (cardOwnerName != null) 'cardOwnerName': cardOwnerName,
      'storeHours': storeHours,
      'temporarilyClosed': temporarilyClosed,
      if (location != null) 'location': location,
    };
  }
}
