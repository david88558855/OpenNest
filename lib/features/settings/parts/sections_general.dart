part of '../settings_page.dart';

/// 「通用」分区（设计稿 D8 侧栏第 1 项）。
///
/// 0.5.0 按设计稿重划侧栏后，原来的「下载目录」「外观」「引擎状态」三个
/// 分区合并进这里，顺序为：
///
///   下载目录 → 引擎状态
///
/// 引擎状态放在最后（它信息量最大、平时很少动），与旧版「引擎状态」在
/// 侧栏底部的位置感一致。
class _GeneralSection extends StatelessWidget {
  const _GeneralSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHead(
          title: '通用',
          subtitle: '下载位置、界面显示与内嵌引擎状态',
        ),
        const _DownloadSection(),
        const _ServersSection(),
      ],
    );
  }
}
