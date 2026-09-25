import 'package:flutter/material.dart';
import 'page_backdrop.dart';

class UserBackdrop extends StatelessWidget {
  const UserBackdrop({super.key, this.alignment = Alignment.center});
  final Alignment alignment;
  @override
  Widget build(BuildContext context) =>
      PageBackdrop(page: 'user', alignment: alignment);
}
