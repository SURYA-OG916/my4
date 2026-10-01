import 'package:flutter/material.dart';

import '../utils/category_colors.dart';

// Day 38: the stock blueAccent is gone. "All" is navy; every other chip uses
// its own category colour (soft tint when idle, full colour when selected),
// so the chips match the list rows and Category Summary.
const Color _navy = Color(0xFF1F2A44);

class CategoryFilterChips extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  const CategoryFilterChips({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selectedCategory;
          final isAll = category == 'All';

          final Color fill = isAll ? _navy : categoryColor(category);
          final Color idleBackground =
              isAll ? const Color(0xFFEDEDEA) : categorySoftColor(category);
          final Color idleLabel =
              isAll ? const Color(0xFF3D3D3D) : categoryLabelColor(category);

          return ChoiceChip(
            label: Text(category),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => onCategorySelected(category),
            selectedColor: fill,
            backgroundColor: idleBackground,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : idleLabel,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13.5,
            ),
          );
        },
      ),
    );
  }
}