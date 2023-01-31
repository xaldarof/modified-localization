import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

const _preservedKeywords = [
  'few',
  'many',
  'one',
  'other',
  'two',
  'zero',
  'male',
  'female',
];

void main(List<String> args) {
  if (_isHelpCommand(args)) {
    _printHelperDisplay();
  } else {
    handleLangFiles(_generateOption(args));
  }
}

bool _isHelpCommand(List<String> args) {
  return args.length == 1 && (args[0] == '--help' || args[0] == '-h');
}

void _printHelperDisplay() {
  var parser = _generateArgParser(null);
  log(parser.usage);
}

GenerateOptions _generateOption(List<String> args) {
  var generateOptions = GenerateOptions();
  var parser = _generateArgParser(generateOptions);
  parser.parse(args);
  return generateOptions;
}

ArgParser _generateArgParser(GenerateOptions? generateOptions) {
  var parser = ArgParser();

  parser.addOption('source-dir',
      abbr: 'S',
      defaultsTo: 'resources/langs',
      callback: (String? x) => generateOptions!.sourceDir = x,
      help: 'Folder containing localization files');

  parser.addOption('source-file',
      abbr: 's',
      callback: (String? x) => generateOptions!.sourceFile = x,
      help: 'File to use for localization');

  parser.addOption('output-dir',
      abbr: 'O',
      defaultsTo: 'lib/generated',
      callback: (String? x) => generateOptions!.outputDir = x,
      help: 'Output folder stores for the generated file');

  parser.addOption('output-file',
      abbr: 'o',
      defaultsTo: 'codegen_loader.g.dart',
      callback: (String? x) => generateOptions!.outputFile = x,
      help: 'Output file name');
  
  parser.addFlag(
    'skip-unnecessary-keys',
    abbr: 'u',
    defaultsTo: false,
    callback: (bool? x) => generateOptions!.skipUnnecessaryKeys = x,
    help: 'If true - Skip unnecessary keys of nested objects.',
  );

  return parser;
}

class GenerateOptions {
  String? sourceDir;
  String? sourceFile;
  String? templateLocale;
  String? outputDir;
  String? outputFile;
  String? format;
  bool? skipUnnecessaryKeys;

  @override
  String toString() {
    return 'format: $format sourceDir: $sourceDir sourceFile: $sourceFile outputDir: $outputDir outputFile: $outputFile skipUnnecessaryKeys: $skipUnnecessaryKeys';
  }
}

void handleLangFiles(GenerateOptions options) async {
  final current = Directory.current;
  final source = Directory.fromUri(Uri.parse(options.sourceDir!));
  final output = Directory.fromUri(Uri.parse(options.outputDir!));
  final sourcePath = Directory(path.join(current.path, source.path));
  final outputPath =
  Directory(path.join(current.path, output.path, options.outputFile));

  if (!await sourcePath.exists()) {
    printError('Source path does not exist');
    return;
  }

  var files = await dirContents(sourcePath);
  if (options.sourceFile != null) {
    final sourceFile = File(path.join(source.path, options.sourceFile));
    if (!await sourceFile.exists()) {
      printError('Source file does not exist (${sourceFile.toString()})');
      return;
    }
    files = [sourceFile];
  } else {
    //filtering format
    files = files.where((f) => f.path.contains('.json')).toList();
  }

  if (files.isNotEmpty) {
    generateFile(files, outputPath, options);
  } else {
    printError('Source path empty');
  }
}

Future<List<FileSystemEntity>> dirContents(Directory dir) {
  var files = <FileSystemEntity>[];
  var completer = Completer<List<FileSystemEntity>>();
  var lister = dir.list(recursive: false);
  lister.listen((file) => files.add(file),
      onDone: () => completer.complete(files));
  return completer.future;
}

void generateFile(List<FileSystemEntity> files, Directory outputPath,
    GenerateOptions options) async {
  var generatedFile = File(outputPath.path);
  if (!generatedFile.existsSync()) {
    generatedFile.createSync(recursive: true);
  }

  var classBuilder = StringBuffer();

  await _writeKeys(classBuilder, files, options.skipUnnecessaryKeys);

  classBuilder.writeln('}');
  generatedFile.writeAsStringSync(classBuilder.toString());

  printInfo('All done! File generated in ${outputPath.path}');
}

Future _writeKeys(StringBuffer classBuilder, List<FileSystemEntity> files,
    bool? skipUnnecessaryKeys) async {
  var file = '''
import 'package:easy_localization/easy_localization.dart';\n
// DO NOT EDIT. This is code generated via package:easy_localization/generate.dart
// Modified by @xaldarof
// See https://github.com/xaldarof/modified-easy-localization

abstract class Strings {
''';

  final fileData = File(files.first.path);

  Map<String, dynamic> translations =
  json.decode(await fileData.readAsString());

  file += _resolve(translations, skipUnnecessaryKeys);

  classBuilder.writeln(file);
}

String _resolve(Map<String, dynamic> translations, bool? skipUnnecessaryKeys,
    [String? accKey]) {
  var fileContent = '';

  final sortedKeys = translations.keys.toList();

  final canIgnoreKeys = skipUnnecessaryKeys == true;

  bool containsPreservedKeywords(Map<String, dynamic> map) =>
      map.keys.any((element) => _preservedKeywords.contains(element));

  for (var key in sortedKeys) {
    var ignoreKey = false;
    if (translations[key] is Map) {
      // If key does not contain keys for plural(), gender() etc. and option is enabled -> ignore it
      ignoreKey = !containsPreservedKeywords(
          translations[key] as Map<String, dynamic>) &&
          canIgnoreKeys;

      var nextAccKey = key;
      if (accKey != null) {
        nextAccKey = '$accKey.$key';
      }

      fileContent +=
          _resolve(translations[key], skipUnnecessaryKeys, nextAccKey);
    }

    if (!_preservedKeywords.contains(key)) {
      var value = translations[key];

      if (value.contains("{}")) {
        var argCount = '{}'
            .allMatches(value)
            .length;
        var arguments = "";
        var argumentsValue = "";
        for (int i = 0; i < argCount; i++) {
          arguments += "String arg$i,";
          argumentsValue += "arg$i,";
        }

        accKey != null && !ignoreKey
            ? fileContent += """
  static String ${toCamelCase(key)}(${arguments.substring(
            0, arguments.length - 1)}) {
    return '${key}'.tr(args: [${argumentsValue.substring(
            0, argumentsValue.length - 1)}]);
  }
"""
            : !ignoreKey
            ? fileContent += """
  static String ${toCamelCase(key)}(${arguments.substring(
            0, arguments.length - 1)}) {
    return '${key}'.tr(args: [${argumentsValue.substring(
            0, argumentsValue.length - 1)}]);
  }
"""
            : null;
      } else {
        accKey != null && !ignoreKey
            ? fileContent +=
        '  static const ${accKey.replaceAll('.', '_')}_${toCamelCase(
            key)} = \'$accKey.$key\'.tr();\n'
            : !ignoreKey
            ?
        fileContent += '  static final ${toCamelCase(key)} = \'$key\'.tr();\n'
            : null;
      }
    }
  }

  return fileContent;
}

String toCamelCase(String str, {String? splitter}) {
  var value = str.split("");
  var valueStr = "";
  for (int i = 0; i < value.length; i++) {
    if (value[i] == (splitter ?? "_")) {
      if (i < value.length) {
        value[i + 1] = value[i + 1].toUpperCase();
        value.removeAt(i);
      }
    }
  }
  for (var element in value) {
    valueStr += element;
  }
  return valueStr;
}

void printInfo(String info) {
  log('\u001b[32measy localization: $info\u001b[0m');
}

void printError(String error) {
  log('\u001b[31m[ERROR] easy localization: $error\u001b[0m');
}
