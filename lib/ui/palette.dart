// Цвета игры — те же, что в css/style.css веб-версии.

import 'package:flutter/painting.dart';

abstract final class Palette {
  static const ground = Color(0xFF07090C);
  static const fog = Color(0xFF090C11);
  static const ink = Color(0xFFEEF1F4);
  static const inkDim = Color(0xFF9AA6B2);
  static const gold = Color(0xFFF2C230); // миссии
  static const cash = Color(0xFF6FCF6A); // деньги
  static const blue = Color(0xFF5AA9FF); // GPS
  static const red = Color(0xFFFF4D5A); // провал, опасность
  static const panel = Color(0xEB0A0D12);
  static const line = Color(0x1FFFFFFF);
  static const chip = Color(0xB3000000);
}
