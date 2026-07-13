import 'package:flutter/material.dart';

import 'debug_console_page.dart';

Future<void> openDebugConsole(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const DebugConsolePage()));
