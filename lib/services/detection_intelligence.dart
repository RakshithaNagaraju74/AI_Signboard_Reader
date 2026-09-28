import 'dart:math' as math;
import '../models/detection_result.dart';

enum SignPosition { left, slightlyLeft, front, slightlyRight, right }
extension SignPositionSpeech on SignPosition { String get label => switch(this){SignPosition.left=>'left',SignPosition.slightlyLeft=>'slightly left',SignPosition.front=>'ahead',SignPosition.slightlyRight=>'slightly right',SignPosition.right=>'right'}; }
class DetectionContext { final DetectionResult detection; final SignPosition position; final double priority; final String movement; const DetectionContext({required this.detection,required this.position,required this.priority,required this.movement}); }
class DetectionIntelligence {
 final Map<String,_Track> _tracks={}; double _frameWidth=416,_frameArea=173056;
 void setFrameSize(int width,int height){_frameWidth=width.toDouble();_frameArea=width*height.toDouble();}
 DetectionContext select(List<DetectionResult> detections){
  if(detections.isEmpty)throw StateError('No detections');
  final contexts=detections.map((d){final cx=(d.bbox[0]+d.bbox[2])/2;final w=math.max(1.0,d.bbox[2]-d.bbox[0]);final h=math.max(1.0,d.bbox[3]-d.bbox[1]);final area=(w*h)/math.max(1.0,_frameArea);final key=_key(d);final previous=_tracks[key];final movement=previous==null?'':area>previous.area*1.12?'getting closer':area<previous.area*.88?'moving farther':'';_tracks[key]=_Track(area,previous?.lastAnnounced);final priority=d.confidence*.55+area.clamp(0,.75)*.25+_safetyBoost(d.className)+(d.ocrText.trim().isNotEmpty?.15:0);return DetectionContext(detection:d,position:_position(cx/_frameWidth),priority:priority,movement:movement);}).toList()..sort((a,b)=>b.priority.compareTo(a.priority));return contexts.first;
 }
 bool shouldAnnounce(DetectionContext c,{Duration cooldown=const Duration(seconds:8)}){final t=_tracks[_key(c.detection)];return t==null||t.lastAnnounced==null||DateTime.now().difference(t.lastAnnounced!)>=cooldown;}
 void markAnnounced(DetectionContext c){final t=_tracks[_key(c.detection)];if(t!=null)t.lastAnnounced=DateTime.now();}
 SignPosition _position(double x){if(x<.20)return SignPosition.left;if(x<.40)return SignPosition.slightlyLeft;if(x<.60)return SignPosition.front;if(x<.80)return SignPosition.slightlyRight;return SignPosition.right;}
 double _safetyBoost(String label){final s=label.toLowerCase();if(s.contains('warning')||s.contains('construction')||s.contains('pedestrian_dont')||s.contains('stop')||s.contains('wet_floor'))return .30;if(s.contains('bus')||s.contains('rail')||s.contains('mrt')||s.contains('school'))return .20;return .05;}
 String _key(DetectionResult d)=>d.className+'|'+d.ocrText.trim().toLowerCase();
}
class _Track{final double area;DateTime? lastAnnounced;_Track(this.area,this.lastAnnounced);}
