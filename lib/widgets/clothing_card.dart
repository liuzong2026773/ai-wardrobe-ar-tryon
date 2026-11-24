import 'dart:io';
import 'package:flutter/material.dart';
import '../data/app_database.dart';

class ClothingCard extends StatelessWidget {
  final ClothingItem item;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;
  const ClothingCard({super.key, required this.item, this.onTap, this.onFavorite});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Container(
              color: Colors.white, // 白底标准图
              width: double.infinity,
              child: Image.file(File(item.imagePath), fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.checkroom, size: 48)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
                InkWell(onTap: onFavorite,
                  child: Icon(item.isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 18, color: item.isFavorite ? Colors.red : Colors.grey)),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 4, children: [
                _chip(item.category),
                _chip(item.colorFamily),
                _chip('穿过 ${item.wearCount} 次'),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
    child: Text(s, style: const TextStyle(fontSize: 11, color: Colors.black87)));
}
