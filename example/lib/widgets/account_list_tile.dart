import 'package:flutter/material.dart';

typedef AccountGestureCallback = void Function(String address);

class AccountListTile extends StatelessWidget {
  final String address;
  final AccountGestureCallback? onTap;

  const AccountListTile({
    required this.address,
    this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(address),
      onTap: () {
        onTap?.call(address);
      },
    );
  }
}
