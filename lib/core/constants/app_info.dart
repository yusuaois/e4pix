/// 应用信息
class AppInfo {
  AppInfo._();

  static const String repoOwner = 'yusuaois';
  static const String repoName = 'e4pix';

  /// 主页
  static const String repoUrl = 'https://github.com/$repoOwner/$repoName';

  /// github.com/owner/repo
  static const String repoDisplay = 'github.com/$repoOwner/$repoName';

  /// GitHub API release
  static const String latestReleaseApi =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
}