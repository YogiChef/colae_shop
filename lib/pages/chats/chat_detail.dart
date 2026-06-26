// Updated ChatdetailPage.dart - Added confirmation button for vendor on pending slips
// ignore_for_file: unnecessary_cast

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:colae_shop/services/sevice.dart';

class ChatdetailPage extends StatefulWidget {
  final String buyerId;
  final String vendorId;
  final String proId;
  final dynamic data;
  const ChatdetailPage({
    super.key,
    required this.vendorId,
    required this.buyerId,
    required this.proId,
    required this.data,
  });

  @override
  State<ChatdetailPage> createState() => _ChatdetailPageState();
}

class _ChatdetailPageState extends State<ChatdetailPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _messageController = TextEditingController();
  late Stream<QuerySnapshot> _chatStream;
  bool _isSending = false;

  @override
  void initState() {
    _chatStream = firestore
        .collection('chats')
        .where('buyerId', isEqualTo: widget.buyerId)
        .where('vendorId', isEqualTo: widget.vendorId)
        .where('proId', isEqualTo: widget.proId)
        .orderBy('chatDate', descending: false)
        .snapshots();
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAllAsRead());
  }

  Future<void> _markAllAsRead() async {
  try {
    final snap = await firestore
        .collection('chats')
        .where('vendorId', isEqualTo: widget.vendorId)
        .where('buyerId', isEqualTo: widget.buyerId)
        .where('proId', isEqualTo: widget.proId)
        .where('senderId', isEqualTo: widget.buyerId) // เฉพาะข้อความจาก buyer
        .get();

    if (snap.docs.isEmpty) return;

    final batch = firestore.batch();
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['read'] != true) {
        batch.update(doc.reference, {'read': true});
      }
    }
    await batch.commit();
  } catch (e) {
    print('[MARK_READ] error: $e');
  }
}

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    if (_isSending) return;
    _isSending = true;

    String message = _messageController.text.trim();
    if (message.isNotEmpty) {
      _messageController.clear();
      try {
        DocumentSnapshot vendorDoc = await firestore
            .collection('vendors')
            .doc(widget.vendorId)
            .get();
        DocumentSnapshot buyerDoc = await firestore
            .collection('buyers')
            .doc(widget.buyerId)
            .get();

        try {
          await FirebaseFirestore.instance.enableNetwork();
        } catch (_) {}
        await firestore.collection('chats').add({        
          'proId': widget.proId,
          'proName': widget.data['proName'] ?? 'Product',
          'buyerName': (buyerDoc.data() as Map<String, dynamic>)['fullName'],
          'buyerPhoto':
              (buyerDoc.data() as Map<String, dynamic>)['profileImage'],
          'vendorPhoto': (vendorDoc.data() as Map<String, dynamic>)['image'],
          'buyerId': widget.buyerId,
          'vendorId': widget.vendorId,
          'message': message,
          'messageType': 'text',
          'senderId': auth.currentUser!.uid,
          'chatDate': FieldValue.serverTimestamp(),
          'read': false,
        });
      } catch (e) {
        _messageController.text = message;
      }
    }

    _isSending = false;
  }

  Widget _buildMessageBubble(
    Map<String, dynamic> data,
    bool isVendorMessage,
    String docId,
  ) {
    final String messageType = data['messageType'] ?? 'text';
    final String? imageUrl = data['imageUrl'];
    final String? messageText = data['message'];

    final bool hasImage = imageUrl != null && imageUrl.isNotEmpty;

    Widget content;

    if (hasImage) {
      content = InkWell(
        onTap: () => _zoomSlip(imageUrl, widget.proId),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            height: 0.35.sh,
            width: 0.5.sw,
            fit: BoxFit.cover,
            memCacheWidth: 800,
            placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
            errorWidget: (_, __, ___) => Container(
              height: 200.h,
              color: Colors.grey.shade300,
              child: const Icon(Icons.error, color: Colors.red),
            ),
          ),
        ),
      );
    } else if (messageType == 'text' &&
        messageText != null &&
        messageText.isNotEmpty) {
      content = Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isVendorMessage ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Text(
          messageText,
          style: styles(
            color: isVendorMessage ? Colors.white : Colors.black87,
            fontSize: 14.sp,
          ),
        ),
      );
    } else {
      content = Text(
        '[ไม่สามารถแสดงข้อความนี้ได้]',
        style: styles(color: Colors.grey),
      );
    }

    return Container(
      constraints: BoxConstraints(maxWidth: 0.75.sw, minWidth: 40.w),
      margin: EdgeInsets.symmetric(horizontal: 8.w),
      child: content,
    );
  }

  void _zoomSlip(String url, String orderId) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text('ดูสลิป Order ID:'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 16.0, left: 16.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ' $orderId',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.fitWidth,
                      memCacheWidth: 1200,
                      placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, error, stackTrace) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error, size: 50, color: Colors.red),
                              SizedBox(height: 16),
                              Text('ไม่สามารถโหลดภาพได้'),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final String proName = widget.data['proName'] ?? 'Chat Detail';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          proName,
          style: styles(
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatStream,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<QuerySnapshot> snapshot,
                  ) {
                    if (snapshot.hasError) {
                      return const Text('Something went wrong');
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return ListView.builder(
                      reverse: false,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final document = snapshot.data!.docs[index];
                        final data = document.data() as Map<String, dynamic>;
                        final bool isVendorMessage =
                            data['senderId'] == auth.currentUser!.uid;
                        final String docId = document.id; // For update

                        return Padding(
                          padding: EdgeInsets.only(bottom: 8.h),
                          child: Row(
                            mainAxisAlignment: isVendorMessage
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isVendorMessage) ...[
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: CircleAvatar(
                                    radius: 16.r,
                                    backgroundImage: CachedNetworkImageProvider(
                                      data['buyerPhoto'] ?? '',
                                    ),
                                    onBackgroundImageError: (_, _) =>
                                        Icon(Icons.person),
                                  ),
                                ),
                                SizedBox(width: 8.w),
                              ],
                              _buildMessageBubble(data, isVendorMessage, docId),
                              if (isVendorMessage) ...[SizedBox(width: 8.w)],
                            ],
                          ),
                        );
                      },
                    );
                  },
            ),
          ),
          120.h.verticalSpace,
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SafeArea(
        child: Container(
          color: Colors.white,
          padding: EdgeInsets.only(
            left: 20.w,
            right: 20.w,
            top: 8.h,
            bottom: MediaQuery.of(context).viewPadding.bottom + 12.h,
          ),
          child: TextFormField(
            controller: _messageController,
            style: styles(color: Colors.black54, fontSize: 16.sp),
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 24.h,
                vertical: 8.w,
              ),
              hintText: 'Type a message',
              hintStyle: styles(
                color: Colors.black38,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
              ),
              suffixIcon: IconButton(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send, color: Colors.blue),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: const BorderSide(
                  width: 0.5,
                  color: Colors.blue,
                  style: BorderStyle.none,
                ),
              ),
            ),
            onFieldSubmitted: (_) => _sendMessage(),
          ),
        ),
      ),
    );
  }
}
