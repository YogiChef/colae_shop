import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:colae_shop/services/sevice.dart';

class CategoryWidget extends StatefulWidget {
  const CategoryWidget({super.key});

  @override
  State<CategoryWidget> createState() => _CategoryWidgetState();
}

class _CategoryWidgetState extends State<CategoryWidget> {
  late final Stream<QuerySnapshot> _categoriesStream;

  @override
  void initState() {
    super.initState();
    _categoriesStream = FirebaseFirestore.instance
        .collection('type')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _categoriesStream,
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return const Text('Something went wrong');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          );
        }

        return SizedBox(
          height: 370,
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.only(top: 6, bottom: 20),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final cateData = snapshot.data!.docs[index];
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  cateData['typename'],
                  style: styles(letterSpacing: 1),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
