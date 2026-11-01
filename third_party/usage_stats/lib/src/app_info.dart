/// An installed application, as the Shield list needs it: its package name,
/// its label and whether it is part of the system image.
///
/// Returned by [UsageStats.queryInstalledApps]. Use [UsageStats.getAppIcon] to
/// fetch the launcher icon separately.
class AppInfo {
  /// Creates an [AppInfo]. Usually constructed via [AppInfo.fromMap].
  AppInfo({
    required this.packageName,
    this.appName,
    required this.isSystemApp,
  });

  /// Builds an [AppInfo] from a platform-channel map.
  factory AppInfo.fromMap(Map<dynamic, dynamic> map) => AppInfo(
        packageName: map['packageName'] as String? ?? '',
        appName: map['appName'] as String?,
        isSystemApp: '${map['isSystemApp']}' == 'true',
      );

  /// The application's package name.
  final String packageName;

  /// The user-visible application label, if it could be resolved.
  final String? appName;

  /// Whether the app is part of the system image.
  final bool isSystemApp;

  @override
  String toString() => 'AppInfo(packageName: $packageName, appName: $appName, '
      'isSystemApp: $isSystemApp)';
}
