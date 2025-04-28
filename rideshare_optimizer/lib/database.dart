

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Database {

static final supabase = Supabase.instance.client;

static Future<void> addRide(double cost, double surgePrice, LatLng dropoff, LatLng? pickup) async {
double destLat = dropoff.latitude;
double destLong = dropoff.longitude;
double pickupLat = pickup!.latitude;
double pickupLong = pickup!.longitude;



PostgrestList id = await supabase
 .from('ride_endpoints')
 .upsert({
  'start_lat':pickupLat, 
  'start_long':pickupLong,
  'end_lat':destLat,
  'end_long':destLong }).select();

var rideId = id.first['ride_id'];

 await supabase 
 .from('ride_costs')
 .insert({'ride_id':rideId, 'base_cost':cost, 'surge_price':surgePrice, 'total_price': cost*surgePrice});
}
}