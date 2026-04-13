// lib/features/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shared_widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'title': 'Bienvenido a VendePro',
      'subtitle': 'El sistema de punto de venta y facturación más moderno para tu negocio. Controla tus ventas de forma inteligente.',
      'icon': Icons.point_of_sale_rounded,
      'color': AppColors.primary,
    },
    {
      'title': 'Control de Inventario',
      'subtitle': 'Lleva un registro preciso de tus productos, recibe alertas de stock bajo y mantén tu inventario siempre al día.',
      'icon': Icons.inventory_2_rounded,
      'color': AppColors.accent,
    },
    {
      'title': 'Sincronización en la Nube',
      'subtitle': 'Tus datos siempre seguros y respaldados en la nube. Trabaja sin internet y sincroniza automáticamente al conectarte.',
      'icon': Icons.cloud_sync_rounded,
      'color': AppColors.success,
    },
  ];

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.darkBg, AppColors.darkSurface],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              color: (page['color'] as Color).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: (page['color'] as Color).withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              page['icon'] as IconData,
                              size: 80,
                              color: page['color'] as Color,
                            ),
                          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                          const SizedBox(height: 60),
                          Text(
                            page['title'] as String,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                          ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2, end: 0),
                          const SizedBox(height: 16),
                          Text(
                            page['subtitle'] as String,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Colors.grey,
                                  height: 1.5,
                                ),
                          ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2, end: 0),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Dots
                    Row(
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 8),
                          height: 8,
                          width: _currentIndex == index ? 24 : 8,
                          decoration: BoxDecoration(
                            color: _currentIndex == index
                                ? AppColors.primary
                                : Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    // Button
                    if (_currentIndex == _pages.length - 1)
                      SizedBox(
                        width: 150,
                        child: GradientButton(
                          label: 'Comenzar',
                          icon: Icons.rocket_launch_rounded,
                          onTap: _completeOnboarding,
                        ),
                      ).animate().fadeIn().slideX(begin: 0.2, end: 0)
                    else
                      TextButton(
                        onPressed: () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: const Text('Siguiente',
                            style: TextStyle(
                              color: AppColors.primaryLight,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            )),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
