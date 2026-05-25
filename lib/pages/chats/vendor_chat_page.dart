import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:colae_shop/pages/chats/chat_detail.dart';
import 'package:colae_shop/services/sevice.dart';

class VendorChatPage extends StatefulWidget {
  const VendorChatPage({super.key});

  @override
  State<VendorChatPage> createState() => _VendorChatPageState();
}

class _VendorChatPageState extends State<VendorChatPage> {
  late final Stream<QuerySnapshot> _vendorChatStream;

  @override
  void initState() {
    super.initState();
    _vendorChatStream = firestore
        .collection('chats')
        .where('vendorId', isEqualTo: auth.currentUser!.uid)
        .orderBy('chatDate', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Message',
          style: styles(fontSize: 22.sp, fontWeight: FontWeight.w500),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _vendorChatStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return const Text('Something went wrong');
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          Map<String, DocumentSnapshot> lastChats = {};
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['senderId'] != auth.currentUser!.uid) {
              // Only buyer messages
              final key = '${data['buyerId']}_${data['proId']}';
              lastChats[key] = doc;
            }
          }

          return ListView.separated(
            reverse: false,
            itemCount: lastChats.length,
            separatorBuilder: (context, index) => Divider(height: 1.h),
            itemBuilder: (context, index) {
              final entry = lastChats.entries.elementAt(index);
              final doc = entry.value;
              final data = doc.data() as Map<String, dynamic>;
              final String proId = data['proId'];
              final String buyerId = data['buyerId'];
              final String messageType = data['messageType'] ?? 'text';
              final String? imageUrl = data['imageUrl'];
              final String preview = messageType == 'slip'
                  ? 'สลิปการชำระเงิน'
                  : (messageType == 'image' && imageUrl != null
                        ? '📷 รูปภาพ'
                        : data['message']);

              return ListTile(
                leading: CircleAvatar(
                  radius: 20.r,
                  backgroundImage: NetworkImage(data['buyerPhoto'] ?? ''),
                  onBackgroundImageError: (_, _) => Icon(Icons.person),
                ),
                title: Text('Id ${proId.substring(0, 8)}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview.length > 50
                          ? '${preview.substring(0, 50)}...'
                          : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if ((messageType == 'image' || messageType == 'slip') &&
                        imageUrl != null)
                      SizedBox(
                        height: 60.h,
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              Icon(Icons.broken_image, size: 20.r),
                        ),
                      ),
                  ],
                ),
                trailing: Text(
                  DateFormat('HH:mm').format(data['chatDate'].toDate()),
                  style: styles(fontSize: 12.sp, color: Colors.grey),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatdetailPage(
                        buyerId: buyerId,
                        vendorId: auth.currentUser!.uid,
                        proId: proId,
                        data: data,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
