import 'package:crypto/crypto.dart';
import 'package:package_config/package_config.dart';
import 'package:yaml/yaml.dart';

import '../artifacts.dart';
import '../base/file_system.dart';
import '../globals.dart' as global;

const String PACKAGE_AOP = 'flutter_aop';
const String FILE_MARK = 'aop_mark.txt';
const String FILE_PACKAGE = '.packages';
const String FILE_PACKAGE_JSON = 'package_config.json';
const String FILE_PUBSPEC = 'pubspec.yaml';
const String DIR_DART_TOOL = '.dart_tool';
const String DIR_FRONTEND_SERVER = 'frontend_server';
const String FILE_FRONTEND_SNAPSHOT = 'frontend_server.dart.snapshot';

const List<String> FEATURES = <String>['constant_optimize'];

class AopHook {
  ///获取Package配置文件
  static File? _getPackageConfigFile() {
    final FileSystem fs = global.fs;
    final String projectPath = fs.currentDirectory.absolute.path;
    final File packageFile = fs.file(fs.path.join(projectPath, FILE_PACKAGE));
    if (packageFile.existsSync()) {
      return packageFile;
    }
    final File packageJsonFile = fs.file(fs.path.join(
      projectPath,
      DIR_DART_TOOL,
      FILE_PACKAGE_JSON,
    ));
    if (packageJsonFile.existsSync()) {
      return packageJsonFile;
    }
    return null;
  }

  ///获取支持AOP的FRONT_END_DIR
  static Future<Directory> _findNewFrondEndDir() async {
    final FileSystem fs = global.fs;
    final File? packageFile = _getPackageConfigFile();
    if (packageFile == null) {
      throw Exception('please run `flutter pub get` first');
    }
    final PackageConfig packageConfig = await loadPackageConfig(packageFile);
    final Package package = packageConfig.packages.firstWhere(
      (Package package) => package.name == PACKAGE_AOP,
      orElse: () => throw Exception('please add $PACKAGE_AOP plugin'),
    );
    final String pluginPath = package.root.toFilePath();
    return fs.directory(fs.path.join(pluginPath, DIR_FRONTEND_SERVER));
  }

  ///获取标记文件
  static File _getMarkFile() {
    final FileSystem fs = global.fs;
    final String snapshotPath = global.artifacts!.getArtifactPath(
      Artifact.frontendServerSnapshotForEngineDartSdk,
    );
    final Directory parentDir = fs.file(snapshotPath).parent;
    return parentDir.childFile(FILE_MARK);
  }

  ///替换原frontend_server.dart.snapshot
  static Future<void> _copySnapshot(Directory newFrontEndDir) async {
    final FileSystem fs = global.fs;
    final File newSnapshot = newFrontEndDir.childFile(FILE_FRONTEND_SNAPSHOT);
    final String newMd5 = md5.convert(newSnapshot.readAsBytesSync()).toString();
    final String oldSnapshotPath = global.artifacts!.getArtifactPath(
      Artifact.frontendServerSnapshotForEngineDartSdk,
    );
    fs.file(oldSnapshotPath).deleteSync();
    newSnapshot.copySync(oldSnapshotPath);
    final File markFile = _getMarkFile();
    if (!markFile.existsSync()) {
      markFile.createSync();
    }
    await markFile.writeAsString(newMd5);
  }

  static bool _needCopySnapShot(Directory newFrontEndDir) {
    final File oldMarkFile = _getMarkFile();
    if (!oldMarkFile.existsSync()) {
      return true;
    }
    final String oldMarkContent = oldMarkFile.readAsStringSync();
    final File newMarkFile = newFrontEndDir.childFile(FILE_MARK);
    return oldMarkContent != newMarkFile.readAsStringSync();
  }

  ///初始化
  static Future<void> initEnv() async {
    final Directory newFrontEndDir = await _findNewFrondEndDir();
    final bool needCopy = _needCopySnapShot(newFrontEndDir);
    global.logger.printStatus('[aop] copy frontend: $needCopy');
    if (needCopy) {
      await _copySnapshot(newFrontEndDir);
    }
  }

  ///当前项目是否开启AOP
  static List<String> useAopParams() {
    final FileSystem fs = global.fs;
    final String projectPath = fs.currentDirectory.absolute.path;
    final String pubspecPath = fs.path.join(projectPath, FILE_PUBSPEC);
    final String yamlContent = fs.file(pubspecPath).readAsStringSync();
    final YamlMap rootYaml = loadYaml(yamlContent) as YamlMap;
    final List<String> params = <String>[];
    final dynamic aopNode = rootYaml['aop'];
    if (aopNode != null && aopNode is YamlMap) {
      for (final String feature in FEATURES) {
        final dynamic status = aopNode[feature];
        if (status != null && status == true) {
          params.add('--$feature');
        }
      }
    }
    global.logger.printStatus('[aop] param: ${params.join(',')}');
    return params;
  }
}
