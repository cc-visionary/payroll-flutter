import 'package:flutter/widgets.dart';

const double kMobileBreakpoint = 600;

bool isMobile(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kMobileBreakpoint;
