

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Database {

static final supabase = Supabase.instance.client;

static Future<void> updateDatabase(double cost, LatLng dropoff, LatLng? pickup) async {
double destLat = dropoff.latitude;
double destLong = dropoff.longitude;
double pickupLat = pickup!.latitude;
double pickupLong = pickup!.longitude;

await supabase
 .from('ride_endpoints')
 .insert({
  'start_lat':pickupLat , 
  'start_long':pickupLong,
  'end_lat':destLat,
  'end_long':destLong,
  });

 await supabase 
 .from('ride_costs')
 .insert({'cost':cost});
}
}