import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/constants/wardrobe_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';

class ClothingCard extends StatelessWidget {
  final ClothingItem item;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const ClothingCard({
    super.key,
    required this.item,
    required this.onToggleFavorite,
    required this.onTap,
  });

  List<String> _parseSeasons() {
    try {
      final decoded = jsonDecode(item.seasons) as List<dynamic>;
      return decoded.map((e) => ClothingSeason.labelOf(e.toString())).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasonLabels = _parseSeasons();
    final fitLabel = FitStyleOption.labelOf(item.fitStyle);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.all(10),
                  child: AspectRatio(
                    aspectRatio: 0.88,
                    child: Image.file(
                      File(item.cutoutImgPath),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.checkroom_outlined,
                        size: 48,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onToggleFavorite,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        item.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 16,
                        color: item.isFavorite
                            ? AppTheme.heartRed
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
                if (item.wearCount > 0)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '穿 ${item.wearCount} 次',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _TagCapsule(item.primaryColor),
                      _TagCapsule(fitLabel),
                      ...seasonLabels.map((s) => _TagCapsule(s)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagCapsule extends StatelessWidget {
  final String text;
  const _TagCapsule(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.tagBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}
