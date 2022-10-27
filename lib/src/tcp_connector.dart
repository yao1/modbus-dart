import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../modbus.dart';
import 'acii_converter.dart';
import 'util.dart';

/// MODBUS TCP Connector
/// Simple protocol details: https://ipc2u.ru/articles/prostye-resheniya/modbus-tcp/
class TcpConnector extends ModbusConnector {
  final Logger log = new Logger('TcpConnector');

  var _address;
  int _port;
  ModbusMode _mode;
  int _tid = 0; //transaction ID
  late int _unitId;
  final Duration? timeout;

  Socket? _socket;
  List<int> tcpBuffer = Uint8List(0); //buffer to store fragmented tcpData

  TcpConnector(this._address, this._port, this._mode, {this.timeout});

  @override
  Future<void> connect() async {
    _socket = await Socket.connect(_address, _port, timeout: this.timeout);
    _socket!.listen(_onData,
        onError: onError, onDone: onClose, cancelOnError: true);
  }

  @override
  Future<void> close() async {
    await _socket?.close();
    _socket?.destroy();
  }

  @override
  void setUnitId(int unitId) {
    _unitId = unitId;
  }

  // void _onData(List<int> tcpData) {
  //   if (_mode == ModbusMode.ascii) tcpData = AsciiConverter.fromAscii(tcpData);
  //
  //   tcpBuffer =
  //       tcpBuffer + tcpData; //add new data to any data already in buffer
  //   log.finest('RECV: ' + dumpHexToString(tcpBuffer));
  //   while (tcpBuffer.length > 8) {
  //     var view = ByteData.view(Uint8List.fromList(tcpBuffer).buffer);
  //     int tid = view.getUint16(0); // ignore: unused_local_variable
  //     int len = view.getUint16(4);
  //     int unitId = view.getUint8(6); // ignore: unused_local_variable
  //     int function = view.getUint8(7);
  //
  //     // check if frame is complete - payload is 2 bytes shorter then length since Modbus length is calculated including unitID and function code
  //     if (tcpBuffer.length >= (8 + len - 2)) {
  //       var payload = tcpBuffer.sublist(8, 8 + len - 2);
  //       tcpBuffer.removeRange(
  //           0, 8 + len - 2); // remove Modbus packet data from buffer
  //       onResponse(function, Uint8List.fromList(payload));
  //     } else {
  //       // not enough bytes in buffer - wait and hope that remaining data is in next TCP frame
  //       break;
  //     }
  //   }
  // }
  void _onData(List<int> tcpData) {
    if (_mode == ModbusMode.ascii) tcpData = AsciiConverter.fromAscii(tcpData);

    tcpBuffer =
        tcpBuffer + tcpData; //add new data to any data already in buffer
    log.finest('RECV: ' + dumpHexToString(tcpBuffer));
    while (tcpBuffer.length >= 8) {
      var view = ByteData.view(Uint8List.fromList(tcpBuffer).buffer);
      int unitId = view.getUint8(0); // ignore: unused_local_variable
      int function = view.getUint8(1);

      // check if frame is complete - payload is 2 bytes shorter then length since Modbus length is calculated including unitID and function code
      //if (tcpBuffer.length >= (8 + len - 2)) {
      var payload = tcpBuffer.sublist(0, 6);
      tcpBuffer.removeRange(0, 8); // remove Modbus packet data from buffer
      onResponse(function, Uint8List.fromList(payload));
      // } else {
      //   // not enough bytes in buffer - wait and hope that remaining data is in next TCP frame
      //   break;
      // }
    }
  }

  @override
  void write(int function, Uint8List data) {
    _tid++;

    // Uint8List tcpHeader = Uint8List(7); // Modbus Application Header
    // ByteData.view(tcpHeader.buffer)
    //   ..setUint16(0, _tid, Endian.big)
    //   ..setUint16(4, 1 /*unitId*/ + 1 /*fn*/ + data.length, Endian.big)
    //   ..setUint8(6, _unitId);

    //为了现场测试，暂时修改一下tcp header内容，之后恢复为上面header
    Uint8List tcpHeader = Uint8List(1); // Modbus Application Header
    ByteData.view(tcpHeader.buffer)..setUint8(0, _unitId);

    Uint8List fn = Uint8List(1); // Modbus Application Header
    ByteData.view(fn.buffer).setUint8(0, function);

    Uint8List tcpData = Uint8List.fromList(
        tcpHeader + fn + data + getCRC(tcpHeader + fn + data));

    log.finest('SEND: ' + dumpHexToString(tcpData));

    if (_mode == ModbusMode.ascii) tcpData = AsciiConverter.toAscii(tcpData);

    _socket!.add(tcpData);
  }

  static Uint8List getCRC(List list) {
    int CRC = 0x000ffff;
    int POLYNOMIAL = 0X0000a001;
    int i, j;
    int length = list.length;
    for (i = 0; i < length; i++) {
      CRC ^= (list[i]);
      for (j = 0; j < 8; j++) {
        if (CRC & 0x00000001 == 1) {
          CRC >>= 1;
          CRC ^= POLYNOMIAL;
        } else {
          CRC >>= 1;
        }
      }
    }
    CRC = ((CRC & 0x0000FF00) >> 8) | ((CRC & 0x000000FF) << 8);
    var checknode = CRC.toRadixString(16);
    //print("校验码:"+checknode);
    Uint8List crcUint8List = Uint8List(2); // Modbus Application Header
    ByteData.view(crcUint8List.buffer).setUint16(0, CRC, Endian.big);
    return crcUint8List;
  }
}
