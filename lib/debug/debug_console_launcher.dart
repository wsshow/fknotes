import 'package:flutter/widgets.dart';

import 'debug_console_launcher_debug.dart'
    if (dart.vm.product) 'debug_console_launcher_noop.dart'
    if (dart.vm.profile) 'debug_console_launcher_noop.dart'
    as implementation;

Future<void> openDebugConsole(BuildContext context) =>
    implementation.openDebugConsole(context);
