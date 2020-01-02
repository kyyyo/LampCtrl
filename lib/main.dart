import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lamp_control/DatabaseService/databaseService.dart';
import 'package:lamp_control/SocketService/socketService.dart';
import 'package:lamp_control/Widgets/AddLamp/addLamp.dart';
import 'package:lamp_control/Widgets/AddLamp/addLampResult.dart';
import 'package:lamp_control/Widgets/AddLamp/lampType.dart';
import 'package:lamp_control/Widgets/LampListItem/setableLamp.dart';
import 'package:lamp_control/Widgets/Settings/settingsResult.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'DatabaseService/Lamp.dart';
import 'Widgets/LampListItem/switchableLamp.dart';
import 'Widgets/Settings/settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(home: Home()));
}

class Home extends StatefulWidget {
  DatabaseService databaseService;
  SharedPreferences config;
  Socket _socket;

  Home() {
    this.databaseService = new DatabaseService();
    this.databaseService.setupDatabase();
    SharedPreferences.getInstance().then((pref) {
      this.config = pref;

      Socket.connect(this.config.get("ip"), this.config.get("port"))
          .then((sock) {
        _socket = sock;
      }).catchError((err) {
        _socket = null;
        print(err.toString());
      });
    });
  }

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Widget> _lamps = List<Widget>.generate(0, null);
  bool _connectionState = false;

  @override
  initState() {
    super.initState();
    List<Widget> tmpLamps = List<Widget>.generate(0, null);
    widget.databaseService.getLamps().then((lamps) {
      lamps.forEach((lamp) {
        if (lamp.type == "LampType.SWITCHABLE")
          tmpLamps.add(new SwitchableLamp(lamp.name, widget._socket, lamp.pin));
        else if (lamp.type == "LampType.SETABLE")
          tmpLamps.add(new SetableLamp(lamp.name, widget._socket, lamp.pin));
      });
      setState(() {
        _lamps = tmpLamps;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text("Lampensteuerung"),
        actions: <Widget>[
          createStreamBuilder(),
          createConnectionIcon(),
          Padding(
            padding: const EdgeInsets.all(0),
            child: IconButton(
              icon: Icon(Icons.settings),
              onPressed: openedSettings,
            ),
          ),
        ],
      ),
      body: Center(
          child: ListView.builder(
        itemCount: _lamps.length,
        itemBuilder: dismissableItemBuilder,
      )),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: addButtonPressed,
      ),
    );
  }

  Widget createConnectionIcon() {
    if (_connectionState)
      return Icon(Icons.check);
    else
      return Icon(Icons.block);
  }

  Widget createStreamBuilder() {
    if (widget._socket != null) {
      _connectionState = true;
      return new StreamBuilder(
        stream: widget._socket,
        builder: handleStream,
      );
    }

    _connectionState = false;
    return Container(
      height: 0.0,
      width: 0.0,
    );
  }

  Widget handleStream(context, snap) {
    if (snap.hasError) {
      print(snap.error.toString());
    } else if (snap.hasData) {
      print(String.fromCharCodes(snap.data));
    }

    //Empty basically not visible container used
    //as dummy to implement streambuilder
    return Container(
      width: 0.0,
      height: 0.0,
    );
  }

  void openedSettings() async {
    final result = await Navigator.push<SettingsResult>(context,
        MaterialPageRoute<SettingsResult>(builder: (context) => Settings()));
    if (result != null) {
      widget.config.setString("ip", result.raspiIp);
      widget.config.setInt("port", result.port);
      Socket.connect(result.raspiIp, result.port).then((sock) {
        List<Widget> tmpLamps = List<Widget>.generate(0, null);
        widget.databaseService.getLamps().then((lamps) {
          lamps.forEach((lamp) {
            if (lamp.type == "LampType.SWITCHABLE")
              tmpLamps
                  .add(new SwitchableLamp(lamp.name, sock, lamp.pin));
            else if (lamp.type == "LampType.SETABLE")
              tmpLamps
                  .add(new SetableLamp(lamp.name, sock, lamp.pin));
          });
          setState(() {
            _lamps = tmpLamps;
            widget._socket = sock;
            _connectionState = true;
          });
        });
      }).catchError((err) {
                List<Widget> tmpLamps = List<Widget>.generate(0, null);
        widget.databaseService.getLamps().then((lamps) {
          lamps.forEach((lamp) {
            if (lamp.type == "LampType.SWITCHABLE")
              tmpLamps
                  .add(new SwitchableLamp(lamp.name, null, lamp.pin));
            else if (lamp.type == "LampType.SETABLE")
              tmpLamps
                  .add(new SetableLamp(lamp.name, null, lamp.pin));
          });
          setState(() {
            _lamps = tmpLamps;
            widget._socket.destroy();
            widget._socket = null;
            _connectionState = false;
          });
        });
        print(err.toString());
      });
    }
  }

  Widget dismissableItemBuilder(BuildContext context, int index) {
    var lamp = _lamps[index];
    return Dismissible(
        key: Key(lamp.toString()),
        child: lamp,
        onDismissed: (direction) {
          setState(() {
            _lamps.removeAt(index);
            widget.databaseService.deleteLamp(lamp.toString()).then((data) {
              Scaffold.of(context)
                ..removeCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(lamp.toString() + " removed"),
                ));
            });
            if (widget._socket != null)
              switch (lamp.runtimeType) {
                case SwitchableLamp:
                  var tmp = lamp as SwitchableLamp;
                  widget._socket.write(tmp.name +
                      ":" +
                      tmp.pin.toString() +
                      ":" +
                      "true" +
                      ":" +
                      "remove");
                  break;
                case SetableLamp:
                  var tmp = lamp as SetableLamp;
                  widget._socket.write(tmp.name +
                      ":" +
                      tmp.pin.toString() +
                      ":" +
                      "false" +
                      ":" +
                      "remove");
                  break;
              }
          });
        });
  }

  void addButtonPressed() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute<AddLampResult>(builder: (context) => AddLamp()),
    );
    setState(() {
      if (result != null) {
        if (result.lampType == LampType.SETABLE)
          _lamps.add(
              new SetableLamp(result.lampName, widget._socket, result.pin));
        else if (result.lampType == LampType.SWITCHABLE)
          _lamps.add(
              new SwitchableLamp(result.lampName, widget._socket, result.pin));
      }
    });
    if (result != null) {
      widget.databaseService.insertLamp(Lamp(
        name: result.lampName,
        type: result.lampType.toString(),
        pin: result.pin,
      ));
      if (widget._socket != null) {
        if (result.lampType == LampType.SWITCHABLE)
          widget._socket.write(result.lampName +
              ":" +
              result.pin.toString() +
              ":" +
              "true" +
              ":" +
              "add");
        if (result.lampType == LampType.SETABLE)
          widget._socket.write(result.lampName +
              ":" +
              result.pin.toString() +
              ":" +
              "false" +
              ":" +
              "add");
      }
    }
  }
}
