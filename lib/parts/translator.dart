import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';

class Dictionary {
  List languages = [];
  bool systemLanguage = false;
  Map dictionary = {};
  String locale = "en";
  String path = "";
  String url = "";

  Dictionary._internal(this.path, this.url);
  factory Dictionary({required String path, required String url}){
    return Dictionary._internal(path, url);
  }

  Future<void> decideLanguage() async {
    final box = Hive.box('paios_storage');
    if (box.containsKey("language")) {
      locale = box.get("language", defaultValue: "en");
    } else {
      await setSystemLanguage();
    }
  }
  
  Future<void> setSystemLanguage() async {
    final box = Hive.box('paios_storage');
    // Remove the saved preference so decideLanguage() falls back to device locale on next boot
    await box.delete("language");
    String deviceLocale = "en";
    try {
      deviceLocale = Platform.localeName.split("_")[0];
    } catch (_) {}
    bool found = false;
    for (int a = 0; a < languages.length; a++) {
      if (languages[a]["id"] == deviceLocale) {
        locale = deviceLocale;
        found = true;
        break;
      }
    }
    if (!found) {
      locale = "en";
    }
  }
  
  saveLanguage(String variant) async {
    final box = Hive.box('paios_storage');
    for(int a = 0; a < languages.length;a++){
      if(languages[a]["id"] == variant){
        locale = variant;
        box.put("language", variant);
      }
    }
  }

  setup({Future<void> Function(String, String, String)? log}) async {
    final box = Hive.box('paios_storage');
    
    // 1. Triple-Tier System Step 1 & 2: Load Cache or Fallback Asset
    String? cachedLangList = box.get("cached_languages_json");
    if (cachedLangList != null) {
      languages = jsonDecode(cachedLangList);
    } else {
      String assetLangList = await rootBundle.loadString('$path/languages.json');
      languages = jsonDecode(assetLangList);
    }
    
    await decideLanguage();
    
    for(int i=0; i < languages.length; i++){
      String langId = languages[i]["id"];
      String? cachedDict = box.get("cached_dict_$langId");
      if (cachedDict != null) {
        dictionary[langId] = jsonDecode(cachedDict);
      } else {
        try {
          String assetDict = await rootBundle.loadString('$path/$langId.json');
          dictionary[langId] = jsonDecode(assetDict);
        } catch (e) {
          // Fails silently if rootBundle doesn't have it (e.g. newly added lang)
        }
      }
    }
    
    // 2. Triple-Tier System Step 3: Network Check & Cache Refresh
    if(!kDebugMode){
      try {
        if (log != null) await log("dict", "info", "Fetching languages from $url/$path/languages.json");
        final response = await http.get(Uri.parse("$url/$path/languages.json"));
        if(response.statusCode == 200) {
          if (log != null) await log("dict", "info", "Language list fetched successfully");
          languages = jsonDecode(response.body);
          box.put("cached_languages_json", response.body); // Update persistent cache
          // Only re-decide language if the user has no saved preference.
          // If they saved one, keep it — never let the network refresh override it.
          if (!box.containsKey("language")) await decideLanguage();
          
          for (int i = 0; i < languages.length; i++) {
            String langId = languages[i]["id"];
            final languageGet = await http.get(Uri.parse("$url/$path/$langId.json"));
            if (languageGet.statusCode == 200) {
              if (log != null) await log("dict", "info", "Downloaded dictionary for $langId");
              dictionary[langId] = jsonDecode(languageGet.body);
              box.put("cached_dict_$langId", languageGet.body); // Update persistent cache
            } else {
              if (log != null) await log("dict", "warning", "Failed to download dictionary for $langId: ${languageGet.statusCode}");
            }
          }
        } else {
          if (log != null) await log("dict", "error", "Failed to fetch language list: ${response.statusCode}");
        }
      }catch(e){
        if (kDebugMode) print("Falling back to strictly offline Languages! Error: $e");
        if (log != null) await log("dict", "error", "Network error during dictionary setup: $e");
      }
    }
  }

  String value (String entry){
    if(!dictionary.containsKey(locale)){
      return "Loading...";
    }
    if(!dictionary[locale].containsKey(entry)){
      if(!dictionary["en"].containsKey(entry)){
        if(kDebugMode) {
          return "!!! $entry";
        }else{
          return entry;
        }
      }
      if(kDebugMode){
        return "!${dictionary["en"][entry].toString()}!";
      }else{
        return dictionary["en"][entry].toString();
      }
    }
    return dictionary[locale][entry].toString();
  }
}
