import 'package:flutter/material.dart';

class RatingChip extends StatelessWidget {
  const RatingChip({
    required this.rating,
    super.key,
  });

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
      ),
      child: Container(
        width: 34,
        decoration: BoxDecoration(
          color: switch (rating) {
            >=5.0 => Colors.blue,
            >=4.0 => Colors.green,
            >=3.0 => Colors.yellow,
            >=2.0 => Colors.orange,
            _ => Colors.red,
          },
          borderRadius: BorderRadius.circular(15),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 5,
          vertical: 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.star,
              color: Colors.white,
              size: 8,
            ),
            const SizedBox(width: 2),
            Text(
              rating.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
