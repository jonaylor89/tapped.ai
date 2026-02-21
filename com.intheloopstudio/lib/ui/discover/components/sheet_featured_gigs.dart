import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/models/opportunity.dart';
import 'package:intheloopapp/ui/common/opportunities_list.dart';
import 'package:intheloopapp/ui/design/tapped_section_header.dart';

class SheetFeaturedGigs extends StatelessWidget {
  const SheetFeaturedGigs({required this.opportunities, super.key});

  final List<Opportunity> opportunities;

  @override
  Widget build(BuildContext context) {
    if (opportunities.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TappedSectionHeader('featured gigs'),
        OpportunitiesList(opportunities: opportunities),
      ],
    );
  }
}
