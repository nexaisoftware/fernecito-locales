/// Skeleton de carga para la lista de Mis eventos.
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import 'shimmer_skeleton.dart';

class SkeletonListaEventos extends StatelessWidget {
  const SkeletonListaEventos({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        return ShimmerSkeleton(
          child: Container(
            height: 148,
            decoration: BoxDecoration(
              color: ColoresLocales.superficie,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ColoresLocales.bordeSuave),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 88, height: 120, borderRadius: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerLine(width: double.infinity, height: 16, borderRadius: 6),
                      SizedBox(height: 8),
                      ShimmerLine(width: 120, height: 12, borderRadius: 6),
                      Spacer(),
                      ShimmerLine(width: 90, height: 28, borderRadius: 50),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
