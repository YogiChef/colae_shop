import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:colae_shop/pages/tabs/edit_tab/published_tab.dart';
import 'package:colae_shop/pages/tabs/edit_tab/unpublished_tab.dart';
import 'package:colae_shop/providers/product_provider.dart';
import 'package:colae_shop/services/sevice.dart';

class EditPage extends StatefulWidget {
  const EditPage({super.key});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final ProductProvider _productProvider;

  @override
  void initState() {
    super.initState();
    _productProvider = ProductProvider();
  }

  @override
  void dispose() {
    _productProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ChangeNotifierProvider.value(
      value: _productProvider,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            elevation: 0,
            centerTitle: true,
            backgroundColor: mainColor,
            automaticallyImplyLeading: false,
            title: Text(
              'แก้ไขสินค้า',
              style: styles(
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            bottom: const TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: [
                Tab(text: 'โชว์สินค้า'),
                Tab(text: 'เตรียมสินค้า'),
              ],
            ),
          ),
          body: const TabBarView(
            physics: NeverScrollableScrollPhysics(),
            children: [PublishedTab(), UnpublishedTab()],
          ),
        ),
      ),
    );
  }
}
