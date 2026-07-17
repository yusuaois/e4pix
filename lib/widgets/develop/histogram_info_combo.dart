import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../native/raw_bridge.dart';
import '../../state/providers.dart';
import 'histogram_panel.dart';
import 'develop_misc_widgets.dart';

/// 立方图与信息组合控件
class HistogramInfoCombo extends ConsumerStatefulWidget {
  final ui.FragmentProgram program;
  final ui.FragmentProgram maskProgram;
  final ui.Image? sourceImage;
  final VoidCallback? onImport;

  const HistogramInfoCombo({
    super.key,
    required this.program,
    required this.maskProgram,
    required this.sourceImage,
    this.onImport,
  });

  @override
  ConsumerState<HistogramInfoCombo> createState() => _HistogramInfoComboState();
}

class _HistogramInfoComboState extends ConsumerState<HistogramInfoCombo> {
  late final PageController _pageController;
  int _currentPage = 0;

  bool _hoverLeft = false;
  bool _hoverRight = false;

  bool get _isDesktop {
    return switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      _ => true,
    };
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    setState(() => _currentPage = page);
  }

  @override
  Widget build(BuildContext context) {
    final params = ref.watch(effectiveParamsProvider);
    final lut = ref.watch(lutNotifierProvider);
    final lutEnabled = ref.watch(effectiveLutEnabledProvider);
    final curveTexture = ref.watch(effectiveCurveTextureProvider);
    final image = ref.watch(imageNotifierProvider).value;
    final isLoading = ref.watch(imageNotifierProvider).isLoading;
    final path = ref.watch(activeFilePathProvider);
    ref.watch(shotsNotifierProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── PageView: histogram / info ──
        SizedBox(
          height: 84,
          child: Stack(
            children: [
              PageView(
                controller: _pageController,
                onPageChanged: (p) => setState(() => _currentPage = p),
                children: [
                  LiveHistogramPanel(
                    program: widget.program,
                    maskProgram: widget.maskProgram,
                    sourceImage: widget.sourceImage,
                    params: params,
                    lutTexture: lutEnabled ? lut.textureA : null,
                    lutSize: lutEnabled ? lut.sizeA : 0,
                    lutTextureB: lutEnabled ? lut.textureB : null,
                    lutSizeB: lutEnabled ? lut.sizeB : 0,
                    curveTexture: curveTexture,
                    height: 84,
                    margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  ),
                  _buildInfoPage(context, image, isLoading, path),
                ],
              ),
              if (_isDesktop)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildHoverArrow(
                    isLeft: true,
                    visible: _hoverLeft && _currentPage > 0,
                    onTap: _currentPage > 0
                        ? () => _goToPage(_currentPage - 1)
                        : null,
                    onHover: (h) => setState(() => _hoverLeft = h),
                  ),
                ),
              if (_isDesktop)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildHoverArrow(
                    isLeft: false,
                    visible: _hoverRight && _currentPage < 1,
                    onTap: _currentPage < 1
                        ? () => _goToPage(_currentPage + 1)
                        : null,
                    onHover: (h) => setState(() => _hoverRight = h),
                  ),
                ),
            ],
          ),
        ),
        // ── Action bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 12, 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  io.Platform.isAndroid
                      ? Icons.folder_copy_outlined
                      : Icons.add_photo_alternate_outlined,
                  size: 16,
                ),
                tooltip: io.Platform.isAndroid
                    ? tr("folderImport")
                    : tr("imageChoose"),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: isLoading ? null : widget.onImport,
              ),
              const SizedBox(width: 8),
              RatingFlagBar(compact: true),
              const Spacer(),
              // 胶囊监视器
              _DotIndicator(current: _currentPage, onTap: _goToPage),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHoverArrow({
    required bool isLeft,
    required bool visible,
    VoidCallback? onTap,
    required ValueChanged<bool> onHover,
  }) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: visible ? 1.0 : 0.0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.only(
              left: isLeft ? 6.0 : 0,
              right: !isLeft ? 6.0 : 0,
            ),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.pureBlack.withValues(alpha: 0.45),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pureBlack.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                isLeft ? Icons.chevron_left : Icons.chevron_right,
                size: 20,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPage(
    BuildContext context,
    DecodedImageState? image,
    bool isLoading,
    String? path,
  ) {
    final m = image?.metadata;
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m?.summary.isNotEmpty == true
                ? m!.summary
                : (path != null ? p.basename(path) : tr('imageNotChosen')),
            style: AppTypography.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (image != null) ...[
            const SizedBox(height: 4),
            Text(
              isPhone
                  ? '${image.width}×${image.height}'
                  : '${image.width}×${image.height} · '
                        '${image.bitsPerChannel}-bit · '
                        'decode ${image.decodeTime.inMilliseconds}ms · '
                        'convert ${image.convertTime.inMilliseconds}ms',
              style: AppTypography.labelSmall.copyWith(
                fontFamily: 'monospace',
                color: AppColors.semanticSuccess.withValues(alpha: 0.75),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (image != null && image.isPreliminary) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 9,
                  height: 9,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.2,
                    color: AppColors.semanticWarning.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  tr('loadingHD'),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.semanticWarning.withValues(alpha: 0.7),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Two tiny filled dots indicating which page is active.
class _DotIndicator extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;

  const _DotIndicator({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => onTap(0),
          child: _Dot(active: current == 0, activeColor: primary),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => onTap(1),
          child: _Dot(active: current == 1, activeColor: primary),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  final Color activeColor;
  const _Dot({required this.active, required this.activeColor});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: active ? 16 : 6,
      height: 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: active
            ? activeColor
            : AppColors.disabledText.withValues(alpha: 0.3),
      ),
    );
  }
}
