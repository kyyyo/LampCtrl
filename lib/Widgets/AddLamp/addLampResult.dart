import 'package:lamp_control/Widgets/AddLamp/lampType.dart';

class AddLampResult {
  final String _lampName;
  final LampType _lampType;
  final int _pin;

  AddLampResult(this._lampName, this._lampType, this._pin);

  LampType get lampType => _lampType;

  String get lampName => _lampName;

  int get pin => _pin;


}