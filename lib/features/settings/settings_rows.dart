import 'package:flutter/material.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';

/// A section's name in settings, and in the sheets it opens.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.title, {this.top = Gap.xl, super.key});

  final String title;

  /// Space above: less at the top of a sheet.
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.xl, top, Gap.xl, Gap.md),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: AppText.metaStrong.copyWith(
            color: Theme.of(context).colors.inkMuted,
          ),
        ),
      ),
    );
  }
}

/// A row that does something at once: an icon, what it does, and a line
/// saying more.
class SettingsAction extends StatelessWidget {
  const SettingsAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colors;
    final detail = this.detail;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.xl,
              vertical: Gap.md,
            ),
            child: Row(
              children: [
                Icon(icon, color: colors.inkMuted),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppText.uiLarge.copyWith(color: colors.ink),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: AppText.ui.copyWith(color: colors.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
