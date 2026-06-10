// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/pages/chats/chat_detail.dart';
import 'package:colae_shop/services/sevice.dart';

class BuyerDetailsWidget extends StatelessWidget {
  final String buyerId;
  final Map orderData;
  final List<Map<String, dynamic>> items;
  final String orderId;
  final Function(String, String) onMarkRead;
  final int unreadCount;

  const BuyerDetailsWidget({
    super.key,
    required this.buyerId,
    required this.orderData,
    required this.items,
    required this.orderId,
    required this.onMarkRead,
    this.unreadCount = 0,
  });

  Widget _buildUnreadBadge(int count) {
    if (count <= 0) return const SizedBox.shrink();
    return Positioned(
      right: 0,
      top: 0,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: count > 9 ? 4.w : 2.w,
          vertical: 2.h,
        ),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: styles(
            fontSize: count > 9 ? 9.sp : 10.sp,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> bi =
        (orderData['buyerInfo'] as Map<String, dynamic>?) ?? {};
    final orderEmail =
        bi['custemail']?.toString() ?? orderData['custemail']?.toString() ?? '';
    final orderPhone =
        bi['custphone']?.toString() ?? orderData['custphone']?.toString() ?? '';
    final orderAddress =
        bi['address']?.toString() ?? orderData['address']?.toString() ?? '';
    final orderFullName =
        bi['fullName']?.toString() ??
        orderData['fullName']?.toString() ??
        'Unknown Buyer';
    final orderBuyerImage =
        bi['buyerImage']?.toString() ??
        orderData['buyerImage']?.toString() ??
        '';

    final Map<String, dynamic> vi =
        (orderData['vendorInfo'] as Map<String, dynamic>?) ?? {};
    final String vAddress =
        vi['vaddress'] as String? ?? orderData['vaddress'] as String? ?? '';
    final String vSubdistrict =
        vi['vsubdistrict'] as String? ??
        orderData['vsubdistrict'] as String? ??
        '';
    final String vDistrict =
        vi['vdistrict'] as String? ?? orderData['vdistrict'] as String? ?? '';
    final String vProvince =
        vi['vprovince'] as String? ?? orderData['vprovince'] as String? ?? '';
    final String vZipcode =
        vi['vzipcode'] as String? ?? orderData['vzipcode'] as String? ?? '';
    final String address = [
      if (vAddress.isNotEmpty) vAddress,
      if (vSubdistrict.isNotEmpty) vSubdistrict,
      if (vDistrict.isNotEmpty) 'อ.$vDistrict',
      if (vProvince.isNotEmpty) 'จ.$vProvince',
      if (vZipcode.isNotEmpty) vZipcode,
    ].join(' ');

    final String firstProId = items.isNotEmpty
        ? items.first['proId']?.toString() ?? ''
        : '';

    final String buyerImageUrl =
        orderBuyerImage.isNotEmpty && orderBuyerImage != 'null'
        ? orderBuyerImage
        : 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(orderFullName)}&background=ff6b35&color=fff&size=128';

    final String email = orderEmail.isNotEmpty ? orderEmail : '';

    final avatarWithBadge = Stack(
      children: [
        CircleAvatar(
          radius: 20.r,
          backgroundImage: NetworkImage(buyerImageUrl),
          backgroundColor: Colors.grey.shade200,
        ),
        _buildUnreadBadge(unreadCount),
      ],
    );

    final Map<String, dynamic>? shippingAddress =
        (orderData['orderType'] as String?) == 'ecommerce'
            ? (orderData['shippingAddress'] as Map<String, dynamic>?)
            : null;

    return GestureDetector(
      onTap: () async {
        if (items.isNotEmpty && firstProId.isNotEmpty) {
          await onMarkRead(buyerId, firstProId);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatdetailPage(
                buyerId: buyerId,
                vendorId: auth.currentUser!.uid,
                proId: firstProId,
                data: orderData,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่พบข้อมูลสินค้าเพื่อเริ่มแชท'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.orange.withAlpha(50),
          border: Border(top: BorderSide(color: Colors.orange.shade200)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ข้อมูลผู้สั่งซื้อ',
              style: styles(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatarWithBadge,
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        orderFullName,
                        style: styles(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                      if (orderAddress.isNotEmpty) ...[
                        SizedBox(height: 4.h),
                        Text(
                          address,
                          style: styles(fontSize: 11.sp, color: Colors.black54),
                        ),
                      ],
                      if (orderPhone.isNotEmpty) ...[
                        SizedBox(height: 4.h),
                        Row(
                          children: [
                            Icon(Icons.phone, size: 16.sp, color: Colors.green),
                            SizedBox(width: 4.w),
                            Expanded(
                              child: Text(
                                orderPhone,
                                style: styles(
                                  fontSize: 12.sp,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (email.isNotEmpty) ...[
                        SizedBox(height: 4.h),
                        Row(
                          children: [
                            Icon(Icons.email, size: 16.sp, color: Colors.blue),
                            SizedBox(width: 4.w),
                            Expanded(
                              child: Text(
                                email,
                                style: styles(
                                  fontSize: 12.sp,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (orderPhone.isEmpty && email.isEmpty) ...[
                        SizedBox(height: 4.h),
                        Text(
                          'No contact details available',
                          style: styles(fontSize: 12.sp, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (shippingAddress != null) ...[
              SizedBox(height: 12.h),
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_shipping, color: Colors.blue[800], size: 18.sp),
                        SizedBox(width: 8.w),
                        Text(
                          'ที่อยู่จัดส่ง',
                          style: styles(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      shippingAddress['name']?.toString() ?? '-',
                      style: styles(fontSize: 12.sp, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      shippingAddress['phone']?.toString() ?? '-',
                      style: styles(fontSize: 12.sp, color: Colors.grey[700]),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      [
                        shippingAddress['address']?.toString() ?? '',
                        shippingAddress['city']?.toString() ?? '',
                        shippingAddress['state']?.toString() ?? '',
                        shippingAddress['country']?.toString() ?? '',
                        shippingAddress['zipcode']?.toString() ?? '',
                      ].where((s) => s.isNotEmpty).join(' '),
                      style: styles(fontSize: 12.sp, color: Colors.grey[800]),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
