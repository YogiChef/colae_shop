// ignore_for_file: sort_child_properties_last, no_leading_underscores_for_local_identifiers

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:colae_shop/pages/tabs/edit_tab/update_product.dart';
import 'package:colae_shop/providers/product_provider.dart';
import 'package:colae_shop/services/sevice.dart';

class PublishedTab extends StatefulWidget {
  const PublishedTab({super.key});

  @override
  State<PublishedTab> createState() => _PublishedTabState();
}

class _PublishedTabState extends State<PublishedTab> {
  late final Stream<QuerySnapshot> _productStream;

  @override
  void initState() {
    super.initState();
    _productStream = FirebaseFirestore.instance
        .collection('products')
        .where('vendorId', isEqualTo: auth.currentUser!.uid)
        .where('approved', isEqualTo: true)
        .snapshots();
  }

  Future<void> _unpublishProduct(String docId) async {
    if (!mounted) return;
    try {
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      await firestore.collection('products').doc(docId).update({
        'approved': false,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unpublish สำเร็จ!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteProduct(String docId) async {
    if (!mounted) return;
    try {
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      await firestore.collection('products').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ลบสำเร็จ!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _productRating(Map<String, dynamic> d) {
    final double avg = (d['averageRating'] as num?)?.toDouble() ?? 0.0;
    final int count = (d['ratingCount'] as num?)?.toInt() ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: 16.sp, color: Colors.amber),
        SizedBox(width: 2.w),
        Text(
          avg.toStringAsFixed(1),
          style: styles(
            fontSize: 11.sp,
            fontWeight: FontWeight.w600,
            color: context.textColor,
          ),
        ),
        // SizedBox(width: 2.w),
        // Text('($count)', style: styles(fontSize: 10.sp, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => Future<void>.value(),
      child: StreamBuilder<QuerySnapshot>(
        stream: _productStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.yellow),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(height: 100.h),
                Image.asset('images/waiting.webp', width: 300.w),
                Center(
                  child: Text(
                    'This Published\nhas no items yet !',
                    style: styles(fontSize: 20.sp, color: Colors.red),
                  ),
                ),
              ],
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            key: const PageStorageKey('published_list'),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final id = doc.id;
              final data = doc.data() as Map<String, dynamic>;

              final List<dynamic>? imageUrls = data['imageUrl'];
              final String imageUrl =
                  (imageUrls != null && imageUrls.isNotEmpty)
                  ? imageUrls[0].toString()
                  : '';
              final bool hasImage = imageUrl.isNotEmpty;
              final int pqty = (data['pqty'] as num?)?.toInt() ?? 0;

              return RepaintBoundary(
                child: Slidable(
                  key: ValueKey(id),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChangeNotifierProvider(
                            create: (_) => ProductProvider(),
                            child: UpdateProductPage(
                              productData: snapshot.data!.docs[index],
                            ),
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              SizedBox(
                                height: 110.w,
                                width: 140.w,
                                child: hasImage
                                    ? CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        fit: BoxFit.cover,
                                      )
                                    : const Icon(Icons.image_not_supported),
                              ),
                              if (pqty <= 0)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black87.withAlpha(60),
                                    child: Center(
                                      child: Text(
                                        'Out of Stock',
                                        style: styles(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data['proName']?.toString() ?? 'Unnamed',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: styles(
                                      fontSize: 13.sp,
                                      color: context.isDark
                                          ? Colors.deepPurple[900]
                                          : Colors.black54,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '$pqty pcs.',
                                        style: styles(
                                          fontSize: 12.sp,
                                          color: context.isDark
                                              ? Colors.white
                                              : pqty <= 10
                                              ? Colors.red
                                              : Colors.black54,
                                        ),
                                      ),
                                      Spacer(),
                                      Text(
                                        '฿${(data['price'] as num?)?.toString() ?? '0'}',
                                        style: styles(
                                          fontSize: 12.sp,
                                          color: context.textColor,
                                        ),
                                      ),
                                    ],
                                  ),

                                  _productRating(data),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  startActionPane: ActionPane(
                    motion: const ScrollMotion(),
                    children: [
                      SlidableAction(
                        onPressed: (_) => _deleteProduct(id),
                        backgroundColor: const Color(0xFFFE4A49),
                        foregroundColor: Colors.white,
                        icon: Icons.delete,
                        label: 'ลบ',
                      ),
                      SlidableAction(
                        onPressed: (_) => _unpublishProduct(id),
                        backgroundColor: mainColor,
                        foregroundColor: Colors.white,
                        icon: Icons.approval_outlined,
                        label: 'ปิดการเผยแพร่',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
