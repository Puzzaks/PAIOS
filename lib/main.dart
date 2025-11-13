import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'engine.dart';
import 'elements.dart';
import 'package:flutter_markdown/flutter_markdown.dart';




void main() {
  runApp(ChangeNotifierProvider(
    create: (context) => aiEngine(),
    child: const MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {


  void initState() {
    super.initState();
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      Provider.of<aiEngine>(context, listen: false).initEngine();
    });
  }
  Widget build(BuildContext context) {
    final _defaultLightColorScheme = ColorScheme.fromSwatch(primarySwatch: Colors.teal);
    final _defaultDarkColorScheme = ColorScheme.fromSwatch(primarySwatch: Colors.teal, brightness: Brightness.dark);
    ThemeData _themeData (colorSheme){
      return ThemeData(
        colorScheme: colorSheme,
        cardTheme: CardThemeData(
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.hardEdge
        ),
        useMaterial3: true,
      );
    }
    TextStyle blacker = const TextStyle(
        color: Colors.black
    );
    return DynamicColorBuilder(builder: (lightColorScheme, darkColorScheme) {
      return MaterialApp(
        theme: _themeData(lightColorScheme ?? _defaultLightColorScheme).copyWith(
            cardColor: Colors.grey,
            iconTheme: const IconThemeData(
                color: Colors.black
            ),
            textTheme: TextTheme(
                displayLarge: blacker,
                displayMedium: blacker,
                displaySmall: blacker,
                headlineLarge: blacker,
                headlineMedium: blacker,
                headlineSmall: blacker,
                titleLarge: blacker,
                titleMedium: blacker,
                titleSmall: blacker,
                bodyLarge: blacker,
                bodyMedium: blacker,
                bodySmall: blacker,
                labelLarge: blacker,
                labelMedium: blacker,
                labelSmall: blacker
            )
        ),
        darkTheme: _themeData(darkColorScheme ?? _defaultDarkColorScheme),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
          double scaffoldHeight = constraints.maxHeight;
          double scaffoldWidth = constraints.maxWidth;
          Cards cards = Cards(context: context);
          return Consumer<aiEngine>(builder: (context, engine, child) {
            Widget settingsDivider(String name,{double leftPadding = 20}){
              return Padding(
                padding: EdgeInsets.only(
                    top:10, left: leftPadding, right: 15, bottom: 5
                ),
                child: Text(
                  name,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w100
                  ),
                ),
              );
            }
            return Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    cards.cardGroup([
                      cardContents.addretract(
                          title: "Temperature",
                          subtitle: engine.temperature.toStringAsFixed(1),
                          actionAdd: (){
                            if(engine.temperature < 0.9){
                              setState(() {
                                engine.temperature = engine.temperature + 0.1;
                              });
                            }
                          },
                          actionRetract: (){
                            if(engine.temperature > 0.1){
                              setState(() {
                                engine.temperature = engine.temperature - 0.1;
                              });
                            }
                          }
                      ),
                      cardContents.addretract(
                          title: "Tokens per response",
                          subtitle: engine.tokens.toString(),
                          actionAdd: engine.tokens > 200?(){}:(){
                              setState(() {
                                engine.tokens = engine.tokens + 50;
                              });
                          },
                          actionRetract: engine.tokens < 99?(){}:(){
                            setState(() {
                              engine.tokens = engine.tokens - 50;
                            });
                          }
                      )
                    ]),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 20
                      ),
                      child: TextField(
                        controller: engine.instructions,
                        decoration: InputDecoration(
                          labelText: 'Instructions for Gemini Nano',
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                          hintText: 'You are a large language model...',
                          helperText:
                          engine.isInitializing?"Saving context now...":'Gamini Nano may not separate these and prompt',
                        ),
                        maxLines: 3,
                        minLines: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 20
                      ),
                      child: TextField(
                        controller: engine.prompt,
                        onChanged: (text){setState(() {});},
                        decoration: const InputDecoration(
                          labelText: 'Prompt',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(20))
                          ),
                          hintText: 'Enter your prompt here',
                          helperText:
                          'There is no context, each response is standalone',
                        ),

                        maxLines: 3,
                        minLines: 1,
                      ),
                    ),
                    engine.isLoading
                    ? Container()
                    : engine.prompt.text.isEmpty?Container():cards.cardGroup([
                      cardContents.tap(
                          title: "Generate",
                          subtitle: engine.isInitialized?engine.isError?"":"Responded in ${((engine.response.generationTimeMs??10)/1000).toStringAsFixed(2)}s, using ${engine.response.tokenCount} tokens (${(engine.response.tokenCount!.toInt()/((engine.response.generationTimeMs??10)/1000)).toStringAsFixed(2)} token/s).":"Initialize with current settings and generate",
                          action: (){engine.generateStream();},
                      )
                    ]),
                    engine.isLoading
                        ? Padding(
                        padding: EdgeInsetsGeometry.all(20),
                    child: LinearProgressIndicator(
                      borderRadius: BorderRadiusGeometry.circular(15),
                    ),)
                        : Container(),
                    if (engine.responseText.isNotEmpty)
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.hardEdge,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(
                                Radius.circular(30)
                            ),
                          ),
                          color: Theme.of(context).colorScheme.onPrimaryFixed,
                          child: Container(
                            width: scaffoldWidth - 30,
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: 20,
                                    horizontal: 20
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    MarkdownBody(
                                      data: !engine.isAvailable
                                        ? "Gemini Nano is not available on this device. Please check if *Google AICore* app is installed and available. The app is designed for Google Pixel phones starting from Pixel 9 series and newer."
                                        : !engine.isInitialized
                                          ? "Gemini Nano is not initialized. If this message is here long enough for you to read it, it means that there is a problem. Please check if *Google AICore* app is installed and available. The app is designed for Google Pixel phones starting from Pixel 9 series and newer."
                                          : engine.responseText,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          });
        }),
      );
    });
  }
}