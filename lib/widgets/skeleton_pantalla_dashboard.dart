/// Skeleton del dashboard home mientras se verifica sesión (como cartelera en usuarios).
library;

import 'package:flutter/material.dart';
import '../core/constants.dart';
import 'shimmer_skeleton.dart';

class SkeletonPantallaDashboard extends StatelessWidget {
  const SkeletonPantallaDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: ColoresLocales.decoracionFondoPantalla,
            ),
          ),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShimmerLine(width: 220, height: 28, borderRadius: 8),
                              const SizedBox(height: 10),
                              ShimmerLine(width: 180, height: 16, borderRadius: 6),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ShimmerBox(width: 118, height: 26, borderRadius: 999),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ShimmerBox(
                      width: double.infinity,
                      height: 44,
                      borderRadius: 999,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: 4,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: ColoresLocales.superficie,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: ColoresLocales.bordeSuave),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerBox(width: 76, height: 76, borderRadius: 20),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ShimmerLine(
                                    width: double.infinity,
                                    height: 18,
                                    borderRadius: 6,
                                  ),
                                  const SizedBox(height: 8),
                                  ShimmerLine(
                                    width: double.infinity,
                                    height: 14,
                                    borderRadius: 6,
                                  ),
                                  const SizedBox(height: 6),
                                  ShimmerLine(width: 180, height: 14, borderRadius: 6),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
