import 'package:flutter/material.dart';
import '../../../../core/constants/wardrobe_constants.dart';
import '../../../../core/theme/app_theme.dart';

class TagEditResult {
  final String name;
  final String category;
  final String primaryColor;
  final String colorHex;
  final List<String> seasons;
  final String fitStyle;
  final int tempMin;
  final int tempMax;

  const TagEditResult({
    required this.name,
    required this.category,
    required this.primaryColor,
    required this.colorHex,
    required this.seasons,
    required this.fitStyle,
    required this.tempMin,
    required this.tempMax,
  });
}

class TagEditorSheet extends StatefulWidget {
  final String initialName;
  final String initialCategory;
  final String initialColor;
  final String initialColorHex;
  final List<String> initialSeasons;
  final String initialFitStyle;
  final int initialTempMin;
  final int initialTempMax;

  const TagEditorSheet({
    super.key,
    required this.initialName,
    required this.initialCategory,
    required this.initialColor,
    required this.initialColorHex,
    required this.initialSeasons,
    required this.initialFitStyle,
    this.initialTempMin = 15,
    this.initialTempMax = 25,
  });

  @override
  State<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<TagEditorSheet> {
  late TextEditingController _nameController;
  late String _category;
  late String _colorName;
  late String _colorHex;
  late Set<String> _seasons;
  late String _fitStyle;
  late RangeValues _tempRange;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _category = widget.initialCategory;
    _colorName = widget.initialColor;
    _colorHex = widget.initialColorHex;
    _seasons = widget.initialSeasons.toSet();
    if (_seasons.isEmpty) _seasons.add('spring');
    _fitStyle = widget.initialFitStyle;
    _tempRange = RangeValues(
      widget.initialTempMin.toDouble().clamp(-10, 40),
      widget.initialTempMax.toDouble().clamp(-10, 40),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '编辑衣物标签',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                TextButton(
                  onPressed: () {
                    final name = _nameController.text.trim().isEmpty
                        ? widget.initialName
                        : _nameController.text.trim();
                    Navigator.of(context).pop(
                      TagEditResult(
                        name: name,
                        category: _category,
                        primaryColor: _colorName,
                        colorHex: _colorHex,
                        seasons: _seasons.toList(),
                        fitStyle: _fitStyle,
                        tempMin: _tempRange.start.round(),
                        tempMax: _tempRange.end.round(),
                      ),
                    );
                  },
                  child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '单品名称',
                filled: true,
                fillColor: AppTheme.tagBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('品类', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ClothingCategory.editableItems.map((cat) {
                final selected = _category == cat.key;
                return ChoiceChip(
                  label: Text(cat.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = cat.key),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('主色系', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ColorPreset.presets.map((preset) {
                final selected = _colorName == preset.name;
                return ChoiceChip(
                  avatar: CircleAvatar(
                    backgroundColor: preset.color,
                    radius: 8,
                  ),
                  label: Text(preset.name),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _colorName = preset.name;
                    _colorHex = preset.hex;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('适用季节', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ClothingSeason.editableItems.map((season) {
                final selected = _seasons.contains(season.key);
                return FilterChip(
                  label: Text(season.label),
                  selected: selected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _seasons.add(season.key);
                      } else if (_seasons.length > 1) {
                        _seasons.remove(season.key);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('版型', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: FitStyleOption.values.map((fit) {
                return ChoiceChip(
                  label: Text(fit.label),
                  selected: _fitStyle == fit.key,
                  onSelected: (_) => setState(() => _fitStyle = fit.key),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              '适穿温度区间: ${_tempRange.start.round()}°C ~ ${_tempRange.end.round()}°C',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            RangeSlider(
              values: _tempRange,
              min: -10,
              max: 40,
              divisions: 50,
              onChanged: (values) => setState(() => _tempRange = values),
            ),
          ],
        ),
      ),
    );
  }
}
