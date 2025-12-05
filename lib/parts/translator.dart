import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

  decideLanguage() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if(prefs.containsKey("language")){
      locale = prefs.getString("language")??"en";
    }else{
      setSystemLanguage();
    }
  }
  setSystemLanguage() async {
    String deviceLocale = Platform.localeName.split("_")[0];
    for(int a = 0; a < languages.length;a++){
      if(languages[a]["id"] == deviceLocale){
        locale = deviceLocale;
      }
    }
  }
  saveLanguage(String variant) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for(int a = 0; a < languages.length;a++){
      if(languages[a]["id"] == variant){
        locale = variant;
        prefs.setString("language", variant);
      }
    }
  }
  setup() async {
    await rootBundle.loadString('$path/languages.json').then((langlist) async {
      languages = jsonDecode(langlist);
      await decideLanguage();
      for(int i=0; i < languages.length; i++){
        await rootBundle.loadString('$path/${languages[i]["id"]}.json').then((langentry) async {
          dictionary[languages[i]["id"]] = jsonDecode(langentry);
        });
      }
    });
    if(!kDebugMode){
      final response = await http.get(
        Uri.parse("$url/$path/languages.json"),
      );
      if(response.statusCode == 200) {
        languages = jsonDecode(response.body);
        await decideLanguage();
        for (int i = 0; i < languages.length; i++) {
          final languageGet = await http.get(
            Uri.parse("$url/$path/${languages[i]["id"]}.json"),
          );
          if (response.statusCode == 200) {
            dictionary[languages[i]["id"]] = jsonDecode(languageGet.body);
          }
        }
      }
    }
  }

  String value (String entry){
    if(!dictionary.containsKey(locale)){
      return "Loading...";
    }
    if(!dictionary[locale].containsKey(entry)){
      if(!dictionary["en"].containsKey(entry)){
        return "!!! $entry";
      }
      return "!${dictionary["en"][entry].toString()}!";
    }
    return dictionary[locale][entry].toString();
  }
}
