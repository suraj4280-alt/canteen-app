import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import 'app_colors.dart';
import 'services/api_service.dart';
import 'meal_state.dart';
import 'meal_pass_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  Timer? _timer;
  String _currentPhase = 'Breakfast';
  String _timeString = '';
  String _countdownString = '';
  bool _hasActiveBooking = false;
  Map<String, dynamic>? _activeBooking;
  final String _adminNotice = ''; // Populated dynamically if needed

  List<dynamic> _meals = [];
  bool _isLoadingMeals = false;
  String? _mealsError;

  @override
  void initState() {
    super.initState();
    _refreshData();
    _fetchMeals();
    _fetchUpcomingBooking();
    MealStateProvider.instance.addListener(_onStateChanged);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshData());
  }

  Future<void> _fetchUpcomingBooking() async {
    try {
      final upcoming = await ApiService.getUpcomingBookings();
      if (mounted && upcoming.isNotEmpty) {
        final currentSlotName = getCurrentSlot();
        final todayStr = DateTime.now().toIso8601String().substring(0, 10);
        
        // Find if the current slot is booked today
        Map<String, dynamic>? currentBooking;
        for (final b in upcoming) {
          if (b['date']?.toString() == todayStr && b['slot_name']?.toString() == currentSlotName) {
            currentBooking = b;
            break;
          }
        }

        if (currentBooking != null) {
          final booking = currentBooking;
          setState(() {
            _hasActiveBooking = true;
            _activeBooking = {
              'meal': booking['slot_name']?.toString() ?? 'Meal',
              'isTomorrow': false,
              'date': booking['date']?.toString() ?? '',
              'orderId': booking['order_id']?.toString() ?? '',
              'status': booking['status_name']?.toString() ?? '',
              'items': <String>[booking['slot_name']?.toString() ?? 'Meal'],
              'bookingId': booking['id'],
            };
          });
        } else {
          setState(() {
            _hasActiveBooking = false;
            _activeBooking = null;
          });
        }
      } else if (mounted) {
        setState(() {
          _hasActiveBooking = false;
          _activeBooking = null;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch upcoming booking: $e');
      if (mounted) {
        setState(() {
          _hasActiveBooking = false;
          _activeBooking = null;
        });
      }
    }
  }

  Future<void> _fetchMeals() async {
    setState(() {
      _isLoadingMeals = true;
      _mealsError = null;
    });
    try {
      final meals = await ApiService.getMeals();
      if (mounted) {
        setState(() {
          _meals = meals;
          _isLoadingMeals = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _mealsError = e.toString().replaceAll('Exception: ', '');
          _isLoadingMeals = false;
        });
      }
    }
  }

  @override
  void dispose() {
    MealStateProvider.instance.removeListener(_onStateChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) _refreshData();
  }

  String? getCurrentSlot() {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute;
    final totalMinutes = h * 60 + m;

    // Use dynamically loaded slot times from API
    if (_meals.isNotEmpty) {
      for (final slot in _meals) {
        final startStr = slot['start_time']?.toString() ?? '';
        final endStr = slot['end_time']?.toString() ?? '';
        if (startStr.length >= 5 && endStr.length >= 5) {
          final start = _timeToMinutes(startStr);
          final end = _timeToMinutes(endStr);
          if (totalMinutes >= start && totalMinutes <= end) {
            return slot['name']?.toString();
          }
        }
      }
    }

    // Meals not loaded yet or no active slot — return null
    return null;
  }


  /// Parses a time string like "07:30:00" into total minutes since midnight.
  int _timeToMinutes(String timeStr) {
    final parts = timeStr.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  Future<void> _refreshData() async {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hr12 = h % 12 == 0 ? 12 : h % 12;
    _timeString =
        '${hr12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $ampm';

    final totalMinutes = h * 60 + m;
    String phase = 'Unknown';
    String countdown = '';

    // Use dynamic slot data from API if available
    if (_meals.isNotEmpty) {
      // Find the current active meal slot (serving time)
      for (final slot in _meals) {
        final startMin = _timeToMinutes(slot['start_time'].toString());
        final endMin = _timeToMinutes(slot['end_time'].toString());
        if (totalMinutes >= startMin && totalMinutes <= endMin) {
          phase = '${slot['name']} (In Progress)';
          break;
        }
      }

      // If no active meal slot, find the next upcoming one
      if (phase == 'Unknown') {
        for (final slot in _meals) {
          final startMin = _timeToMinutes(slot['start_time'].toString());
          if (totalMinutes < startMin) {
            phase = '${slot['name']} (upcoming)';
            break;
          }
        }
        if (phase == 'Unknown') {
          phase = _meals.first['name'] ?? 'Breakfast';
        }
      }

      // Find next open booking window
      // Check same-day windows (offset=0)
      for (final slot in _meals) {
        final offset = slot['booking_open_day_offset'] ?? 0;
        final openStr = slot['booking_open_time']?.toString();
        final closeStr = slot['booking_cutoff_time']?.toString();
        if (openStr == null || closeStr == null) continue;
        
        final openMin = _timeToMinutes(openStr);
        final closeMin = _timeToMinutes(closeStr);
        
        if (offset == 0) {
          // Same-day window for today's meal
          if (totalMinutes >= openMin && totalMinutes < closeMin) {
            final diffMin = closeMin - totalMinutes;
            final dh = diffMin ~/ 60;
            final dm = diffMin % 60;
            countdown = "${slot['name']} booking closes in ${dh}h ${dm}m";
            break;
          } else if (totalMinutes < openMin) {
            final diffMin = openMin - totalMinutes;
            final dh = diffMin ~/ 60;
            final dm = diffMin % 60;
            countdown = "${slot['name']} booking opens in ${dh}h ${dm}m";
            break;
          }
        } else if (offset == -1) {
          // Prev-day window: this is for tomorrow's meal, opens today evening
          if (totalMinutes >= openMin && totalMinutes < closeMin) {
            final diffMin = closeMin - totalMinutes;
            final dh = diffMin ~/ 60;
            final dm = diffMin % 60;
            countdown = "Tomorrow's ${slot['name']} booking closes in ${dh}h ${dm}m";
            break;
          } else if (totalMinutes < openMin) {
            final diffMin = openMin - totalMinutes;
            final dh = diffMin ~/ 60;
            final dm = diffMin % 60;
            countdown = "Tomorrow's ${slot['name']} booking opens in ${dh}h ${dm}m";
            break;
          }
        }
      }
      if (countdown.isEmpty) {
        countdown = "All booking windows closed for today";
      }
    }

    if (mounted) {
      setState(() {
        _currentPhase = phase.replaceAll(' (upcoming)', '').replaceAll(' (In Progress)', '');
        _countdownString = countdown;
      });
    }
  }

  /// Pull-to-refresh handler — reloads all data
  Future<void> _handleRefresh() async {
    await Future.wait([
      _fetchMeals(),
      _fetchUpcomingBooking(),
    ]);
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _handleRefresh,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 110),
                    child: Column(
                      children: [
                        _buildMealArcSection(),
                        const SizedBox(height: 16),
                        _buildNoticeStrip(),
                        const SizedBox(height: 16),
                        _buildActiveBookingCard(),
                        const SizedBox(height: 24),
                        _buildMealsList(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // FAB
          Positioned(bottom: 90, right: 16, child: _buildFAB()),
          // Bottom Nav
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final user = ApiService.currentUser;
    final firstName = user?['firstName'] ?? 'Student';
    final room = user?['room'] ?? '---';
    final hostel = user?['hostel'] ?? '---';
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : 'S';

    return Container(
      color: AppColors.background,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 24,
        right: 24,
        bottom: 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFEAE8E3),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, $firstName',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    'ROOM $room • HOSTEL $hostel',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.background,
            ),
            child: const Icon(
              Icons.notifications_outlined,
              color: AppColors.primary,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealArcSection() {
    return Column(
      children: [
        SizedBox(
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Circular arc chart
              CustomPaint(
                size: const Size(280, 280),
                painter: _MealArcPainter(),
              ),
              // Center text
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentPhase,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'CURRENT PHASE',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 2,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _timeString,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        // Booking reminder — sits below the arc with clear separation
        const SizedBox(height: 20),
        Column(
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                children: [
                  TextSpan(
                    text: _countdownString,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/meal-booking'),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Go to Meal Booking",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 14, color: AppColors.primary),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoticeStrip() {
    final notice = _countdownString.isNotEmpty ? _countdownString : _adminNotice;
    if (notice.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.noticeBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.campaign_outlined,
            color: AppColors.notice,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notice,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.notice,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveBookingCard() {
    if (!_hasActiveBooking || _activeBooking == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.textMuted.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No upcoming meal booked.',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    final meal = _activeBooking!['meal'] as String;
    final isTomorrow = _activeBooking!['isTomorrow'] as bool;
    final orderId = _activeBooking!['orderId'] as String;
    final items = _activeBooking!['items'] as List<String>;

    final displayItems = items.take(3).toList();
    final extraCount = items.length - 3;
    final tags = displayItems.map((item) => _Tag(item)).toList();
    if (extraCount > 0) {
      tags.add(_Tag('+$extraCount more'));
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.textMuted.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$meal booked',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  orderId,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${isTomorrow ? "Tomorrow" : "Today"} • Dining Hall A',
            style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          // Tags
          Wrap(spacing: 8, runSpacing: 8, children: tags),
          const SizedBox(height: 20),
          // CTA Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(999),
              ),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MealPassScreen(
                        bookingId: _activeBooking!['bookingId'] as int?,
                        orderID: _activeBooking!['orderId'] as String?,
                        bookedDate: _activeBooking!['date'] as String?,
                        location: 'Hostel ${ApiService.currentUser?['hostel'] ?? '---'}',
                        bookedSlots: [_activeBooking!['meal'] as String],
                        slotItems: {_activeBooking!['meal'] as String: _activeBooking!['items'] as List<String>},
                        isCompleted: _activeBooking!['status'] == 'used',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Show Meal Token',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealsList() {
    if (_isLoadingMeals) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_mealsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.red.shade400, size: 32),
              const SizedBox(height: 8),
              Text(
                _mealsError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _fetchMeals,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    final currentSlotName = getCurrentSlot();
    final displayedMeals = _meals.where((meal) => meal['name'] == currentSlotName).toList();

    if (displayedMeals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Current Active Meal',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            SizedBox(height: 12),
            Text('No active meal slot right now.', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Active Meal',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayedMeals.length,
            itemBuilder: (context, index) {
              final meal = displayedMeals[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(meal['name'] ?? 'Meal', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${meal['start_time']} - ${meal['end_time']}'),
                  leading: const Icon(Icons.restaurant, color: AppColors.primary),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/meal-booking'),
      child: Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x40944A00),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.home_outlined, 'activeIcon': Icons.home, 'label': 'HOME'},
      {
        'icon': Icons.restaurant_menu_outlined,
        'activeIcon': Icons.restaurant_menu,
        'label': 'MENU',
      },
      {
        'icon': Icons.confirmation_number_outlined,
        'activeIcon': Icons.confirmation_number,
        'label': 'TOKEN',
      },
      {
        'icon': Icons.history_outlined,
        'activeIcon': Icons.history,
        'label': 'HISTORY',
      },
      {
        'icon': Icons.person_outline,
        'activeIcon': Icons.person,
        'label': 'PROFILE',
      },
    ];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.95),
          border: Border(
            top: BorderSide(
              color: const Color(0xFFE7E5E4).withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.textMuted.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: tabs.asMap().entries.map((e) {
            final i = e.key;
            final tab = e.value;
            final isActive = _currentTab == i;
            return GestureDetector(
              onTap: () {
                setState(() => _currentTab = i);
                if (i == 1) Navigator.pushNamed(context, '/meal-booking');
                if (i == 2) {
                  if (_hasActiveBooking && _activeBooking != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MealPassScreen(
                        bookingId: _activeBooking!['bookingId'] as int?,
                        orderID: _activeBooking!['orderId'] as String?,
                        bookedDate: _activeBooking!['date'] as String?,
                        location: 'Hostel ${ApiService.currentUser?['hostel'] ?? '---'}',
                        bookedSlots: [_activeBooking!['meal'] as String],
                        slotItems: {_activeBooking!['meal'] as String: _activeBooking!['items'] as List<String>},
                        isCompleted: _activeBooking!['status'] == 'used',
                      ),
                      ),
                    );
                  } else {
                    Navigator.pushNamed(context, '/meal-pass');
                  }
                }
                if (i == 3) Navigator.pushNamed(context, '/history');
                if (i == 4) Navigator.pushNamed(context, '/profile');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: isActive
                    ? BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      )
                    : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isActive
                          ? tab['activeIcon'] as IconData
                          : tab['icon'] as IconData,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.textDisabled,
                      size: 22,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tab['label'] as String,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? AppColors.primary
                            : AppColors.textDisabled,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.tagBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.tagText,
        ),
      ),
    );
  }
}

class _MealArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 - 20;
    const strokeWidth = 24.0;

    // Full 360° ring split into three equal segments (120° each).
    // Green (completed) → Orange (current) → Gray (upcoming)
    const startAngle = -math.pi / 2; // top of circle
    const segment = math.pi * 2 / 3; // 120°
    // Tiny overlap so rounded caps hide any hairline seam
    const overlap = 0.02;

    final greenPaint = Paint()
      ..color = const Color(0xFF1A6B4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final orangePaint = Paint()
      ..color = const Color(0xFFE67E22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final grayPaint = Paint()
      ..color = const Color(0xFFD6D3CE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // Draw back-to-front so the leading arc's rounded cap overlaps neatly
    // Gray arc — upcoming meals (120°)
    canvas.drawArc(
      rect,
      startAngle + segment * 2,
      segment + overlap,
      false,
      grayPaint,
    );
    // Orange arc — current meal (120°), starts where green ends
    canvas.drawArc(
      rect,
      startAngle + segment,
      segment + overlap,
      false,
      orangePaint,
    );
    // Green arc — completed meals (120°), drawn last so its cap sits on top
    canvas.drawArc(rect, startAngle, segment + overlap, false, greenPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}
