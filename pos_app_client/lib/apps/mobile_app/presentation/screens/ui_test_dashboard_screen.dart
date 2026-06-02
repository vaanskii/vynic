// UI TEST / PREVIEW SCREEN — not wired into production data.
// Standalone hardcoded dashboard mock used to preview a new mobile look.
// Safe to delete; only referenced from the mobile login navigation for testing.
import 'dart:ui';
import 'package:flutter/material.dart';

/// Entry widget for the preview. Wrapped in its own dark [Theme] so it looks
/// identical regardless of the host app's theme.
class UiTestDashboardScreen extends StatelessWidget {
  const UiTestDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050508),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF8B5CF6),
          surface: Color(0xFF111116),
        ),
        useMaterial3: true,
      ),
      child: const _DashboardScreen(),
    );
  }
}

/// ------------------------------------------------------------------
/// MAIN DASHBOARD SCREEN
/// ------------------------------------------------------------------
class _DashboardScreen extends StatefulWidget {
  const _DashboardScreen();

  @override
  State<_DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<_DashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      body: Stack(
        children: [
          // 1. Dynamic Background Blurs
          Positioned(
            top: -100,
            left: -100,
            child: _GlowOrb(color: Color(0xFF3B82F6), size: 300),
          ),
          Positioned(
            top: 200,
            right: -150,
            child: _GlowOrb(color: Color(0xFF8B5CF6), size: 400),
          ),
          Positioned(
            bottom: 0,
            left: 50,
            child: _GlowOrb(color: Color(0xFF10B981), size: 250),
          ),

          // 2. Main Scrollable Content
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 16),
                        _FadeInSlide(
                          controller: _animController,
                          delay: 0.0,
                          child: const _TopHeader(),
                        ),
                        SizedBox(height: 32),
                        _FadeInSlide(
                          controller: _animController,
                          delay: 0.2,
                          child: const _OverviewSection(),
                        ),
                        SizedBox(height: 32),
                        _FadeInSlide(
                          controller: _animController,
                          delay: 0.4,
                          child: const _QuickActionsSection(),
                        ),
                        SizedBox(height: 32),
                        _FadeInSlide(
                          controller: _animController,
                          delay: 0.6,
                          child: const _PopularDishesSection(),
                        ),
                        SizedBox(height: 32),
                        _FadeInSlide(
                          controller: _animController,
                          delay: 0.7,
                          child: const _WaitersSection(),
                        ),
                        SizedBox(height: 32),
                        _FadeInSlide(
                          controller: _animController,
                          delay: 0.8,
                          child: const _LiveActivitySection(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Floating Bottom Navigation
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: _FloatingBottomNav(),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// SECTIONS
/// ------------------------------------------------------------------

class _TopHeader extends StatelessWidget {
  const _TopHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good Evening,',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 4),
              const Text(
                'Giorgi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _BouncingButton(
                onTap: () {},
                child: GlassContainer(
                  padding: const EdgeInsets.all(12),
                  shape: BoxShape.circle,
                  child: Stack(
                    children: [
                      const Icon(Icons.notifications_outlined,
                          color: Colors.white),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFFEF4444),
                                blurRadius: 4,
                                spreadRadius: 1,
                              )
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              SizedBox(width: 16),
              _BouncingButton(
                onTap: () {},
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.2), width: 2),
                    image: const DecorationImage(
                      image: NetworkImage(
                          'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?ixlib=rb-1.2.1&auto=format&fit=facearea&facepad=2&w=256&h=256&q=80'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: "Today's Overview"),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Revenue',
                  value: 4250,
                  prefix: '₾',
                  trend: '+12.5%',
                  isPositive: true,
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _StatCard(
                  title: 'Total Orders',
                  value: 142,
                  trend: '+8.2%',
                  isPositive: true,
                  icon: Icons.receipt_long_rounded,
                  iconColor: const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Active Tables',
                  value: 18,
                  suffix: '/24',
                  trend: 'High',
                  isPositive: true,
                  icon: Icons.table_restaurant_rounded,
                  iconColor: const Color(0xFFF59E0B),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _StatCard(
                  title: 'Reservations',
                  value: 45,
                  trend: '-2.0%',
                  isPositive: false,
                  icon: Icons.book_online_rounded,
                  iconColor: const Color(0xFFEC4899),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection();

  @override
  Widget build(BuildContext context) {
    final actions = [
      {
        'title': 'ახალი\nრეზერვაცია',
        'icon': Icons.add_circle_outline,
        'color': const Color(0xFF3B82F6)
      },
      {
        'title': 'მაგიდის\nგახსნა',
        'icon': Icons.lock_open_rounded,
        'color': const Color(0xFF10B981)
      },
      {
        'title': 'მენიუს\nრედაქტირება',
        'icon': Icons.restaurant_menu,
        'color': const Color(0xFFF59E0B)
      },
      {
        'title': 'თანამშრომლის\nდამატება',
        'icon': Icons.person_add_alt_1,
        'color': const Color(0xFF8B5CF6)
      },
      {
        'title': 'ფინანსების\nნახვა',
        'icon': Icons.pie_chart_outline,
        'color': const Color(0xFFEC4899)
      },
      {
        'title': 'Push\nშეტყობინება',
        'icon': Icons.send_rounded,
        'color': const Color(0xFF06B6D4)
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: _SectionHeader(title: "სწრაფი ქმედებები"),
        ),
        SizedBox(height: 16),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              return _BouncingButton(
                onTap: () {},
                child: Container(
                  width: 110,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: GlassContainer(
                    padding: const EdgeInsets.all(16),
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(action['icon'] as IconData,
                            color: action['color'] as Color, size: 28),
                        SizedBox(height: 12),
                        Text(
                          action['title'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PopularDishesSection extends StatelessWidget {
  const _PopularDishesSection();

  @override
  Widget build(BuildContext context) {
    final dishes = [
      {
        'name': 'Truffle Steak',
        'orders': '48 Orders',
        'revenue': '₾2,400',
        'image':
            'https://images.unsplash.com/photo-1600891964092-4316c288032e?q=80&w=600&auto=format&fit=crop'
      },
      {
        'name': 'Salmon Tartare',
        'orders': '36 Orders',
        'revenue': '₾1,260',
        'image':
            'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?q=80&w=600&auto=format&fit=crop'
      },
      {
        'name': 'Signature Pasta',
        'orders': '65 Orders',
        'revenue': '₾1,820',
        'image':
            'https://images.unsplash.com/photo-1473093295043-cdd812d0e601?q=80&w=600&auto=format&fit=crop'
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: _SectionHeader(title: "Trending Dishes", action: "See Menu"),
        ),
        SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: dishes.length,
            itemBuilder: (context, index) {
              final dish = dishes[index];
              return _BouncingButton(
                onTap: () {},
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    image: DecorationImage(
                      image: NetworkImage(dish['image']!),
                      fit: BoxFit.cover,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.8),
                          Colors.black,
                        ],
                        stops: [0.4, 0.8, 1.0],
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          dish['name']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              dish['orders']!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              dish['revenue']!,
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WaitersSection extends StatelessWidget {
  const _WaitersSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: "Top Waiters Today", action: "All Staff"),
          SizedBox(height: 16),
          GlassContainer(
            padding: const EdgeInsets.all(8),
            borderRadius: BorderRadius.circular(24),
            child: Column(
              children: [
                _WaiterRow(
                  name: "Ana Beridze",
                  revenue: "₾1,205",
                  rating: 4.9,
                  orders: 24,
                  imageUrl:
                      "https://images.unsplash.com/photo-1494790108377-be9c29b29330?q=80&w=150&auto=format&fit=crop",
                  isFirst: true,
                ),
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                _WaiterRow(
                  name: "Luka Maisuradze",
                  revenue: "₾980",
                  rating: 4.7,
                  orders: 19,
                  imageUrl:
                      "https://images.unsplash.com/photo-1599566150163-29194dcaad36?q=80&w=150&auto=format&fit=crop",
                  isFirst: false,
                ),
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                _WaiterRow(
                  name: "Nino Kapanadze",
                  revenue: "₾850",
                  rating: 4.8,
                  orders: 16,
                  imageUrl:
                      "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?q=80&w=150&auto=format&fit=crop",
                  isFirst: false,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _LiveActivitySection extends StatelessWidget {
  const _LiveActivitySection();

  @override
  Widget build(BuildContext context) {
    final activities = [
      {
        'title': 'New Reservation',
        'time': 'Just now',
        'desc': 'Table 4 for 2 persons at 20:00',
        'color': const Color(0xFF3B82F6),
        'icon': Icons.book_online
      },
      {
        'title': 'Table Paid',
        'time': '2 min ago',
        'desc': 'Table 12 paid ₾145.00 via Card',
        'color': const Color(0xFF10B981),
        'icon': Icons.check_circle
      },
      {
        'title': 'Table Opened',
        'time': '5 min ago',
        'desc': 'Ana opened Table 8',
        'color': const Color(0xFFF59E0B),
        'icon': Icons.lock_open
      },
      {
        'title': 'Revenue Milestone',
        'time': '15 min ago',
        'desc': 'Daily revenue crossed ₾4,000!',
        'color': const Color(0xFF8B5CF6),
        'icon': Icons.emoji_events
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionHeader(title: "Live Activity"),
              SizedBox(width: 8),
              _LiveIndicator(),
            ],
          ),
          SizedBox(height: 16),
          GlassContainer(
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(24),
            child: Column(
              children: List.generate(activities.length, (index) {
                final act = activities[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (act['color'] as Color).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(act['icon'] as IconData,
                            size: 16, color: act['color'] as Color),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  act['title'] as String,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                                Text(
                                  act['time'] as String,
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              act['desc'] as String,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                );
              }),
            ),
          )
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// REUSABLE COMPONENTS & WIDGETS
/// ------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String title;
  final int value;
  final String? prefix;
  final String? suffix;
  final String trend;
  final bool isPositive;
  final IconData icon;
  final Color iconColor;

  const _StatCard({
    required this.title,
    required this.value,
    this.prefix = '',
    this.suffix = '',
    required this.trend,
    required this.isPositive,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPositive
                      ? const Color(0xFF10B981).withOpacity(0.1)
                      : const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  trend,
                  style: TextStyle(
                    color: isPositive
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            ],
          ),
          SizedBox(height: 16),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: const Duration(seconds: 2),
            curve: Curves.easeOutCubic,
            builder: (context, val, child) {
              return Text(
                '${prefix ?? ''}$val${suffix ?? ''}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              );
            },
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaiterRow extends StatelessWidget {
  final String name;
  final String revenue;
  final double rating;
  final int orders;
  final String imageUrl;
  final bool isFirst;

  const _WaiterRow({
    required this.name,
    required this.revenue,
    required this.rating,
    required this.orders,
    required this.imageUrl,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: NetworkImage(imageUrl),
              ),
              if (isFirst)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.star, size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star, color: Color(0xFFF59E0B), size: 14),
                    SizedBox(width: 4),
                    Text(
                      rating.toString(),
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7), fontSize: 13),
                    ),
                    SizedBox(width: 12),
                    Text(
                      '$orders orders',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5), fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            revenue,
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;

  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        if (action != null)
          _BouncingButton(
            onTap: () {},
            child: Text(
              action!,
              style: const TextStyle(
                color: Color(0xFF6366F1),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _FloatingBottomNav extends StatefulWidget {
  const _FloatingBottomNav();

  @override
  State<_FloatingBottomNav> createState() => _FloatingBottomNavState();
}

class _FloatingBottomNavState extends State<_FloatingBottomNav> {
  int _selectedIndex = 0;
  final items = ['დაფა', 'მაგიდები', 'ფინანსები', 'რეზერვ.', 'მართვა'];
  final icons = [
    Icons.dashboard_rounded,
    Icons.table_bar_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.book_online_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      borderRadius: BorderRadius.circular(40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(items.length, (index) {
          final isSelected = _selectedIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedIndex = index),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icons[index],
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                    size: 24,
                  ),
                  SizedBox(height: 4),
                  if (isSelected)
                    Text(
                      items[index],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// UTILITIES & EFFECTS
/// ------------------------------------------------------------------

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ??
          (shape == BoxShape.circle
              ? BorderRadius.zero
              : BorderRadius.circular(0)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            shape: shape,
            borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
            color: Colors.white.withOpacity(0.03),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator();

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFEF4444),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0xFFEF4444), blurRadius: 6, spreadRadius: 2)
          ],
        ),
      ),
    );
  }
}

class _FadeInSlide extends StatelessWidget {
  final AnimationController controller;
  final Widget child;
  final double delay;

  const _FadeInSlide({
    required this.controller,
    required this.child,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(delay, 1.0, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - animation.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _BouncingButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _BouncingButton({required this.child, required this.onTap});

  @override
  State<_BouncingButton> createState() => _BouncingButtonState();
}

class _BouncingButtonState extends State<_BouncingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
