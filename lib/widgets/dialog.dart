import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:colae_shop/services/sevice.dart';

class MyAlertDialog {
  static void showMyDialog({
    required BuildContext context,
    required ImageProvider<Object> img,
    required String title,
    required String contant,
    required Function() tabNo,
    required Function() tabYes,
  }) {
    showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: Column(
          children: [
            Image(image: img, width: 120, height: 100),
            Text(title),
          ],
        ),
        content: Text(contant),
        actions: <CupertinoDialogAction>[
          CupertinoDialogAction(
            onPressed: tabNo,
            child: const Text('No', style: TextStyle(color: Colors.green)),
          ),
          CupertinoDialogAction(
            onPressed: tabYes,
            child: Text('Yes', style: styles(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class LoginDialog {
  static void showLoginDialog(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('please log in', style: styles()),
        content: Text(
          'you should be logged in to take an action',
          style: styles(),
        ),
        actions: <CupertinoDialogAction>[
          CupertinoDialogAction(
            child: Text('Cancel', style: styles()),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          CupertinoDialogAction(
            child: Text(
              'Log in',
              style: styles(color: Colors.red, fontWeight: FontWeight.w600),
            ),
            onPressed: () {
              Navigator.pushReplacementNamed(context, 'customer_login');
            },
          ),
        ],
      ),
    );
  }
}
