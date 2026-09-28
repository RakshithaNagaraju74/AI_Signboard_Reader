import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DetectionHistoryEntry {
  final String label, text, position;
  final double confidence;
  final double? latitude, longitude;
  final DateTime timestamp;
  DetectionHistoryEntry({required this.label, required this.text, required this.position, required this.confidence, required this.latitude, required this.longitude, required this.timestamp});

  Map<String,dynamic> toJson()=>{'label':label,'text':text,'position':position,'confidence':confidence,'latitude':latitude,'longitude':longitude,'timestamp':timestamp.toIso8601String()};

  factory DetectionHistoryEntry.fromJson(Map<String,dynamic> j)=>DetectionHistoryEntry(
    label:j['label']??'', text:j['text']??'', position:j['position']??'ahead',
    confidence:(j['confidence']??0).toDouble(), latitude:(j['latitude'] as num?)?.toDouble(),
    longitude:(j['longitude'] as num?)?.toDouble(), timestamp:DateTime.tryParse(j['timestamp']??'')??DateTime.now());
}

class HistoryService {
  static const _key='detection_history';
  Future<List<DetectionHistoryEntry>> read() async {
    final p=await SharedPreferences.getInstance();
    return (p.getStringList(_key)??[]).map((s){try{return DetectionHistoryEntry.fromJson(jsonDecode(s));}catch(_){return null;}}).whereType<DetectionHistoryEntry>().toList();
  }
  Future<void> add(DetectionHistoryEntry e) async {
    final p=await SharedPreferences.getInstance();
    final all=await read(); all.insert(0,e);
    await p.setStringList(_key, all.take(50).map((x)=>jsonEncode(x.toJson())).toList());
  }
}
