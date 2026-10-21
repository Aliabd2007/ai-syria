import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';

class ModeBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const ModeBar({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: AppConstants.modes.map((mode) {
          final isSelected = mode == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text('${AppConstants.modeIcons[mode]} ${AppConstants.modeLabels[mode]}'),
              selected: isSelected,
              onSelected: (_) => onSelect(mode),
            ),
          );
        }).toList(),
      ),
    );
  }
}
