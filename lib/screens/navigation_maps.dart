import 'dart:io';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_place/google_place.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:projectblindcare/screens/turnbyturn.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:projectblindcare/components/camera_view.dart';
import '../components/scan_controller.dart';
import '../constants/constant.dart';
import 'package:alan_voice/alan_voice.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main(){
  runApp(mapPage());
}

class mapPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NavMaps',
      home: LocationMap(),
    );
  }
}

class LocationMap extends StatefulWidget {
  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  _LocationMapState(){
    AlanVoice.addButton(
      "689e5df914105717e09b84ae8ac4018d2e956eca572e1d8b807a3e2338fdd0dc/stage",
      buttonAlign: AlanVoice.BUTTON_ALIGN_RIGHT,
    );
    AlanVoice.activate();
    AlanVoice.onCommand.add((command) {
      debugPrint("got new command ${command.toString()}");});
    AlanVoice.onCommand.add((command) => _handleCommand(command.data));
  }
  Future<void> _handleCommand(Map<String, dynamic> command) async {
    switch(command["command"]) {
      case "getPlace":
        _destinationController.clear();
        _destinationController.text = command["text"];
        _lastWords = _destinationController.text;
        startProcessSubOne();
        break;
      case "getSelect":
        _numberSelect = true;
        _numberController.text = command["text"];
        startProcessSubTwo();
        break;
      default:
        debugPrint("Unknown command");
    }
  }
  @override
  void initState(){
    super.initState();
    _requestLocationPermission();
    apiKey = 'AIzaSyALmRQFrUjSDzXK4TgxPM6iBvnfU6wfhuc';
    googlePlace = GooglePlace(apiKey);
    endFocusNode = FocusNode();
    _navReady = false;
  }
  @override
  void dispose() {
    endFocusNode.dispose();
    _destinationController.dispose();
    _numberController.dispose();
    scanController.dispose();
    super.dispose();
  }

  late TextEditingController _numberController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  GoogleMapController? mapController;
  Set<Marker> markers = {};
  Position? currentPosition;
  late GooglePlace googlePlace;
  List<AutocompletePrediction> predictions = [];
  DetailsResult? endPosition;
  late FocusNode endFocusNode;
  double? s1,s2,e1,e2;
  Map<PolylineId, Polyline> polylines = {};
  List<LatLng> polylineCoordinates = [];
  PolylinePoints polylinePoints = PolylinePoints();
  String apiKey = "AIzaSyALmRQFrUjSDzXK4TgxPM6iBvnfU6wfhuc";
  bool _navReady = false;
  String _lastWords = '';
  String _numValue = '';
  bool _predictionsRead = false;
  bool _numberSelect = false;
  final FlutterTts _flutterTts = FlutterTts();
  ScanController scanController = ScanController();
  var detectedText;
  Future<bool> _checkIsActive() async {
    var isActive = await AlanVoice.isActive();
    if (isActive) {
      return true;
    } else {
      return false;
    }
  }

  void initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.awaitSpeakCompletion(true);
  }
  _speak(String textSpeech) async {
    if (await _checkIsActive() == false) {
      if(!textSpeech.toLowerCase().contains("others")){
        await _flutterTts.speak(textSpeech);
        await _flutterTts.awaitSpeakCompletion(true);
      }
    }
  }
  int? _getNumValue(){
    try {
      return int.parse(_numberController.text)-1;
    } catch (e){
      return null;
    }
  }
  startProcessSubOne() async {
    _enterDestination();
    await Future.delayed(Duration(seconds: 5));
    await _readPredictions();
    await Future.delayed(Duration(seconds: 3));
    await _selectLocation();
  }
  startProcessSubTwo() async {
    await _setData();
    Future.delayed(Duration(seconds: 3));
    if (_navReady){
      _requestLocationPermission();
      _setDestination();
      _getPolyline();
    }
  }
  _enterDestination() async {
    predictions.clear();
    _lastWords = _destinationController.text;
    autoCompleteSearch(_lastWords);
    _predictionsRead = false;
    _numberSelect = false;
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF2FEFE),
      appBar: AppBar(
        backgroundColor: mainThemeColor,
        title: const Text(
          "Navigation",
          style: TextStyle(
              color: Colors.black,
              fontFamily: 'Poppins'
          ),
        ),
      ),
      body: Stack(
        children: [
          if (currentPosition != null)
            GoogleMap(
              polylines: Set<Polyline>.of(polylines.values),
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: LatLng(
                  currentPosition!.latitude ?? 0.0,
                  currentPosition!.longitude ?? 0.0,
                ),
                zoom: 15.0,
              ),
              myLocationEnabled: true,
              markers: markers,
              padding: const EdgeInsets.only(top: 100.0),
            ),
          Positioned(
            top: 10.0,
            left: 10.0,
            right: 10.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _destinationController,
                  focusNode: endFocusNode,
                  decoration: InputDecoration(
                      hintText: 'Enter Destination',
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.9),
                      border: const OutlineInputBorder(),
                      suffixIcon: _destinationController.text.isNotEmpty ?
                      IconButton(
                        onPressed: (){
                          setState(() {
                            predictions = [];
                            _destinationController.clear();
                          });
                        }, icon: const Icon(Icons.clear_outlined),
                      )
                          :null),
                    onChanged: (value) {
                    if (value.isNotEmpty) {
                      autoCompleteSearch(value);
                    } else {
                      setState(() {
                        predictions = [];
                        endPosition = null;
                      });
                    }
                  },
                ),
                Container(
                  color: Colors.blueGrey,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: predictions.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(
                          predictions[index].description.toString(),
                        ),
                        onTap: () async {
                          final placeId = predictions[index].placeId!;
                          final details = await googlePlace.details.get(placeId);
                          if(details != null && details.result != null && mounted) {
                            setState(() {
                              endPosition = details.result;
                              _destinationController.text = details.result!.name!;
                              predictions = [];
                            });
                          }
                        },
                      );
                    },
                  ),
                )
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 10,
            right: 75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: TextButton(
                    onPressed: () async {
                      // _requestLocationPermission();
                      // _setDestination();
                      // _getPolyline();
                    },
                    child: Text('Start', style: TextStyle(color: Colors.white)),
                  ),
                ),
                SizedBox(height: 10),
              ],
            ),
          ),
          Positioned(
            left: 5,
            top: MediaQuery.sizeOf(context).height / 5,
            child: Column(
              children: [
                Container(
                    width: MediaQuery.sizeOf(context).width/3,
                    height: MediaQuery.sizeOf(context).height/3,
                    child: CameraView()
                    ),
                Container(
                    width: MediaQuery.sizeOf(context).width/3,
                    height: MediaQuery.sizeOf(context).height/7,
                    child: Obx(() => objSpeech())
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
  objSpeech() {
    detectedText = Get.find<ScanController>().detectionResult.value;
    _speak(detectedText);
    return Text(detectedText);
  }
  void autoCompleteSearch(String value) async{
    var result = await googlePlace.autocomplete.get(
        value,
        region: "LK",
    );
    print("runner");
    print(result?.predictions);
    if(result != null && result.predictions != null && mounted){
      setState(() {
        predictions = result.predictions!;
      });
    }
  }
  Future<void> _readPredictions() async {
    if (_predictionsRead){
      return null;
    }
    if (predictions.isNotEmpty) {
      for (int i = 0; i < predictions.length; i++) {
        int x = i + 1;
        String num = "0"+x.toString();
        AlanVoice.playText(num);
        String placePredictions = predictions[i].description.toString();
        AlanVoice.playText(placePredictions);
        _predictionsRead = true;
      }
    }
  }
  Future<void> _selectLocation() async {
    if (_numberSelect){
      return null;
    }
    if (predictions.isEmpty){
      return null;
    }
    String _selectString = "Select a number";
    AlanVoice.playText(_selectString);

    _numValue = '';
    _numValue = _numberController.text;
    _numberSelect = true;
  }
  _setData() async {
    AlanVoice.playText(_numValue);
    int? num = _getNumValue();
    try{
      if (num!<0 || num>= predictions.length) {
        _navReady = false;
        return null;
      }
      final placeId = predictions[num].placeId!;
      final details = await googlePlace.details.get(placeId);
      if (details != null && details.result != null) {
        setState(() {
          endPosition = details.result;
          _destinationController.text = details.result!.name!;
          String finalPlace = _numberController.text+_destinationController.text;
          AlanVoice.playText(finalPlace);
          predictions = [];
          _navReady = true;
        });
      } else {
        _navReady = false;
      }
    }
    catch (e){
      _navReady = false;
    }
  }
  void _onMapCreated(GoogleMapController controller){
    setState(() {
      mapController = controller;
    });
  }
  void _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
      );
      setState(() {
        currentPosition = position;
        markers.clear();
        markers.add(
            Marker(
              markerId: MarkerId('Start'),
              position: LatLng(position.latitude, position.longitude),
            )
        );
      });
    }
    catch (e){
      debugPrint('$e');
    }
  }
  Future<void> _requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();
    if (status == PermissionStatus.granted) {
      _getCurrentLocation();
    } else if (status == PermissionStatus.permanentlyDenied) {
      openAppSettings();
    } else {
      debugPrint('error');
    }
  }
  void openAppSettings() async {
    final url = Platform.isAndroid
        ? 'package:com.android.settings'
        : 'app-settings://';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(url as Uri);
    } else {
      debugPrint('error');
    }
  }
  void _setDestination() async {
    s1 = currentPosition?.latitude;
    s2 = currentPosition?.longitude;
    e1 = endPosition!.geometry!.location!.lat!;
    e2 = endPosition!.geometry!.location!.lng!;

    double? ne1, ne2, sw1, sw2;
    if(s1!>e1!){
      ne1 = s1;
      sw1 = e1;
    } else{
      ne1 = e1;
      sw1 = s1;
    }
    if(s2!>e2!){
      ne2 = s2;
      sw2 = e2;
    } else{
      ne2 = e2;
      sw2 = s2;
    }
    mapController!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
            southwest: LatLng(sw1!-0.1,sw2!-0.1),
            northeast: LatLng(ne1!+0.1,ne2!+0.1)),
        1
    ));
    markers.remove('End');
    setState(() {
      markers.add(
        Marker(
          markerId: MarkerId('End'),
          position: LatLng(
              endPosition!.geometry!.location!.lat!,
              endPosition!.geometry!.location!.lng!
          ),
        ),
      );
    });
  }
  _addPolyLine() {
    PolylineId id = PolylineId("poly");
    Polyline polyline = Polyline(
        polylineId: id, color: Colors.red, points: polylineCoordinates);
    polylines[id] = polyline;
    setState(() {});
  }
  _getPolyline() async {
    polylineCoordinates.clear();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      apiKey,
      PointLatLng(s1!, s2!),
      PointLatLng(e1!, e2!),
      travelMode: TravelMode.driving,
    );
    if (result.points.isNotEmpty) {
      result.points.forEach((PointLatLng point) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      });
    }
    _addPolyLine();
    await Future.delayed(Duration(seconds: 2), ()
    {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) =>
            TurnByTurnScreen(
              startLatitude: s1!,
              startLongitude: s2!,
              endLatitude: endPosition!.geometry!.location!.lat!,
              endLongitude: endPosition!.geometry!.location!.lng!,
            ),
        ),
      );
      },
    );
  }
}