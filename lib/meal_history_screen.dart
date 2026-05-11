import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'meal_pass_screen.dart';
import 'meal_state.dart';
import 'services/api_service.dart';

class MealHistoryEntry {
  final String date;
  final String mealType;
  final String menuName;
  final String items;
  final String status; // 'COMPLETED', 'BOOKED', 'SKIPPED', 'CANCELLED'
  final String orderID;
  final int bookingId;
  final String? skipReason;
  final String rawMealType;
  final List<String> rawItemsList;

  MealHistoryEntry({
    required this.date,
    required this.mealType,
    required this.menuName,
    required this.items,
    required this.status,
    required this.orderID,
    required this.bookingId,
    this.skipReason,
    required this.rawMealType,
    required this.rawItemsList,
  });
}

class MealHistoryScreen extends StatefulWidget {
  const MealHistoryScreen({super.key});

  @override
  State<MealHistoryScreen> createState() => _MealHistoryScreenState();
}

class _MealHistoryScreenState extends State<MealHistoryScreen> {
  bool _isLoading = true;
  List<MealHistoryEntry> _allEntries = [];
  Map<String, String> _slotCutoffData = {}; // Slot name → raw cutoff time from API
  String _activeFilter = 'All';
  final List<String> _filters = [
    'All',
    'Booked',
    'Skipped',
    'Completed',
    'Cancelled',
    'Missed',
  ];

  String _dateFilter = 'All Time';
  final List<String> _dateFilterOptions = [
    'All Time',
    'Today',
    'Yesterday',
    'Last 7 Days',
    'Last 30 Days',
  ];

  @override
  void initState() {
    super.initState();
    _loadSlotCutoffs();
    _loadHistory();
    MealStateProvider.instance.addListener(_onStateChanged);
  }

  Future<void> _loadSlotCutoffs() async {
    try {
      final slots = await ApiService.getMeals();
      if (mounted && slots.isNotEmpty) {
        setState(() {
          _slotCutoffData = Map.fromIterables(
            slots.map((s) => s['name']?.toString() ?? ''),
            slots.map((s) => s['booking_cutoff_time']?.toString() ?? ''),
          );
        });
      }
    } catch (_) {
      // Fallback: leave empty, _isCutoffPassed will return true for past dates
    }
  }

  void _onStateChanged() {
    if (mounted) _loadHistory();
  }

  @override
  void dispose() {
    MealStateProvider.instance.removeListener(_onStateChanged);
    super.dispose();
  }

  String _statusLabel(String statusName) {
    switch (statusName) {
      case 'used': return 'COMPLETED';
      case 'booked': return 'BOOKED';
      case 'skipped': return 'SKIPPED';
      case 'cancelled': return 'CANCELLED';
      case 'pending': return 'PENDING';
      case 'expired': return 'EXPIRED';
      case 'absent': return 'NO SHOW';
      case 'missed': return 'MISSED';
      default: return statusName.toUpperCase();
    }
  }

  Future<void> _loadHistory() async {
    try {
      final data = await ApiService.getBookingHistory(page: 1, size: 100);
      final items = data['items'] as List<dynamic>;
      final entries = <MealHistoryEntry>[];

      for (final item in items) {
        final dateStr = item['date']?.toString() ?? '';
        final slotName = item['slot_name']?.toString() ?? 'Meal';
        final statusName = item['status_name']?.toString() ?? 'booked';
        final orderId = item['order_id']?.toString() ?? '';
        final bookingId = item['id'] as int? ?? 0;
        final skipReason = item['skip_reason']?.toString();

        entries.add(MealHistoryEntry(
          date: dateStr,
          mealType: slotName,
          menuName: '$slotName Menu',
          items: '', // items are not in this response — that's fine
          status: _statusLabel(statusName),
          orderID: orderId,
          bookingId: bookingId,
          skipReason: skipReason,
          rawMealType: slotName,
          rawItemsList: [],
        ));
      }

      entries.sort((a, b) {
        final dateCmp = b.date.compareTo(a.date);
        if (dateCmp != 0) return dateCmp;
        return a.rawMealType.compareTo(b.rawMealType);
      });

      if (mounted) {
        setState(() {
          _allEntries = entries;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDisplayDate(String ymd) {
    try {
      final parts = ymd.split('-');
      final date = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
    } catch (_) {
      return ymd;
    }
  }

  bool _isCutoffPassed(String ymd, String mealType) {
    final now = DateTime.now();
    try {
      final parts = ymd.split('-');
      final mealDate = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );

      if (mealDate.isBefore(DateTime(now.year, now.month, now.day))) {
        return true;
      }
      if (mealDate.isAfter(DateTime(now.year, now.month, now.day))) {
        return false;
      }

      // Use API cutoff times from loaded slot data
      final cutoffStr = _slotCutoffData[mealType] ?? '';
      if (cutoffStr.length >= 5) {
        final timeParts = cutoffStr.split(':');
        final cutoffHour = int.tryParse(timeParts[0]) ?? 0;
        final cutoffMinute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
        final cutoffTime = DateTime(
          now.year,
          now.month,
          now.day,
          cutoffHour,
          cutoffMinute,
        );
        return now.isAfter(cutoffTime);
      }

      // Fallback: if no API data, assume cutoff passed for safety
      return true;
    } catch (_) {
      return true;
    }
  }

  void _showCancelDialog(MealHistoryEntry entry) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Are you sure you want to cancel ${entry.rawMealType} on ${_formatDisplayDate(entry.date)}?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Go Back'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        final response = await ApiService.cancelBooking(entry.bookingId);
                        if (response.statusCode == 200) {
                          MealStateProvider.instance.notifyStateChanged();
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to cancel booking'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    child: const Text(
                      'Confirm',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _undoSkip(MealHistoryEntry entry) async {
    try {
      final response = await ApiService.undoSkipBooking(entry.bookingId);
      if (response.statusCode == 200) {
        MealStateProvider.instance.notifyStateChanged();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Skip undone successfully'), backgroundColor: AppColors.primary),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to undo skip'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<MealHistoryEntry> get _filteredEntries {
    var list = _allEntries;
    if (_activeFilter != 'All') {
      list = list
          .where((e) => e.status.toLowerCase() == _activeFilter.toLowerCase())
          .toList();
    }

    if (_dateFilter != 'All Time') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      list = list.where((e) {
        final parts = e.date.split('-');
        final d = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );

        if (_dateFilter == 'Today') {
          return d.isAtSameMomentAs(today);
        } else if (_dateFilter == 'Yesterday') {
          return d.isAtSameMomentAs(today.subtract(const Duration(days: 1)));
        } else if (_dateFilter == 'Last 7 Days') {
          return d.isAfter(today.subtract(const Duration(days: 7))) ||
              d.isAtSameMomentAs(today.subtract(const Duration(days: 7)));
        } else if (_dateFilter == 'Last 30 Days') {
          return d.isAfter(today.subtract(const Duration(days: 30))) ||
              d.isAtSameMomentAs(today.subtract(const Duration(days: 30)));
        }
        return true;
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _loadHistory,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryStats(),
                          _buildFilterTabs(),
                          if (_filteredEntries.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textDisabled),
                                    const SizedBox(height: 12),
                                    Text(
                                      _activeFilter == 'All' ? 'No meal history yet' : 'No ${_activeFilter.toLowerCase()} meals found',
                                      style: const TextStyle(fontSize: 15, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            _buildHistoryList(),
                        ],
                      ),
                    ),
                  ),
          ),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
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
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  color: AppColors.textDark,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Meal History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (val) => setState(() => _dateFilter = val),
            child: Row(
              children: [
                Text(
                  _dateFilter == 'All Time' ? 'Date Filter' : _dateFilter,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.filter_list,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ),
            itemBuilder: (ctx) => _dateFilterOptions
                .map((f) => PopupMenuItem(value: f, child: Text(f)))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStats() {
    int totalBooked = _allEntries.where((e) => e.status == 'BOOKED').length;
    int totalCompleted = _allEntries.where((e) => e.status == 'COMPLETED').length;
    int totalSkipped = _allEntries.where((e) => e.status == 'SKIPPED').length;
    int totalCancelled = _allEntries.where((e) => e.status == 'CANCELLED').length;
    int totalMissed = _allEntries.where((e) => e.status == 'MISSED').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildStatCard('Booked', totalBooked.toString())),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Completed', totalCompleted.toString())),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('Skipped', totalSkipped.toString())),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Cancelled', totalCancelled.toString())),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Missed', totalMissed.toString())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFEDEAE6), width: 1),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filters.map((filter) {
            final isActive = _activeFilter == filter;
            int count = filter == 'All'
                ? _allEntries.length
                : _allEntries
                      .where(
                        (e) => e.status.toLowerCase() == filter.toLowerCase(),
                      )
                      .length;

            return GestureDetector(
              onTap: () => setState(() => _activeFilter = filter),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: isActive ? AppColors.primaryGradient : null,
                  color: isActive ? null : AppColors.inputBackground,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Text(
                      filter,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.white : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isActive ? Colors.white : AppColors.textMuted,
                        ),
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

  Widget _buildHistoryList() {
    final entries = _filteredEntries;

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
        child: Center(
          child: Column(
            children: const [
              Icon(Icons.history, size: 48, color: AppColors.textDisabled),
              SizedBox(height: 16),
              Text(
                'No meal history yet. Start booking meals!',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'HISTORY',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              if (_dateFilter != 'All Time')
                GestureDetector(
                  onTap: () => setState(() => _dateFilter = 'All Time'),
                  child: const Text(
                    'Clear Filter',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ...entries.map((entry) => _buildHistoryCard(entry)),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(MealHistoryEntry entry) {
    Color badgeBg;
    Color badgeText;

    switch (entry.status) {
      case 'COMPLETED':
        badgeBg = const Color(0xFFE8F5E9);
        badgeText = AppColors.success;
        break;
      case 'SKIPPED':
        badgeBg = const Color(0xFFF3F4F6);
        badgeText = AppColors.textMuted;
        break;
      case 'CANCELLED':
        badgeBg = const Color(0xFFFFEBEE);
        badgeText = Colors.red;
        break;
      case 'MISSED':
        badgeBg = const Color(0xFFFFF3E0);
        badgeText = Colors.orange;
        break;
      case 'BOOKED':
      default:
        badgeBg = const Color(0xFFE8F5E9);
        badgeText = AppColors.success;
        break;
    }

    final displayDate = _formatDisplayDate(entry.date);
    final isCutoffPassed = _isCutoffPassed(entry.date, entry.rawMealType);
    final isBooked = entry.status == 'BOOKED';
    final isSkipped = entry.status == 'SKIPPED';

    final showItems =
        isBooked || entry.status == 'COMPLETED' || entry.status == 'CANCELLED';
    final itemText = showItems ? entry.items : 'Meal Skipped';

    return GestureDetector(
      onTap: () {
        if (!isBooked && entry.status != 'COMPLETED') return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) {
              final user = ApiService.currentUser;
              final fn = user?['firstName'] ?? '';
              final ln = user?['lastName'] ?? '';
              final fullName = '$fn $ln'.trim();
              return MealPassScreen(
                studentName: fullName.isNotEmpty ? fullName : 'Student',
                roomNumber: user?['room'] ?? '---',
                orderID: entry.orderID,
                bookingId: entry.bookingId,
                bookedDate: displayDate,
                location: 'Hostel ${user?['hostel'] ?? '---'}',
                bookedSlots: [entry.rawMealType],
                slotItems: {entry.rawMealType: entry.rawItemsList},
                isCompleted: entry.status == 'COMPLETED',
              );
            },
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEDEAE6), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: badgeText.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  entry.status,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: badgeText,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.inputBackground,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.rice_bowl,
                    color: AppColors.primary,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.mealType,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.menuName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        itemText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isSkipped && entry.skipReason != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Reason: ${entry.skipReason}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 12,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$displayDate • 12:15 PM',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            entry.orderID,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (isBooked)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Tooltip(
                              message: isCutoffPassed
                                  ? 'Cancellation window has closed.'
                                  : '',
                              child: OutlinedButton(
                                onPressed: isCutoffPassed
                                    ? null
                                    : () => _showCancelDialog(entry),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 0,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  side: BorderSide(
                                    color: isCutoffPassed
                                        ? Colors.grey.shade300
                                        : Colors.red.shade300,
                                  ),
                                  foregroundColor: Colors.red,
                                  disabledForegroundColor: Colors.grey,
                                ),
                                child: const Text(
                                  'Cancel Booking',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (isSkipped && !isCutoffPassed)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () => _undoSkip(entry),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 0,
                                ),
                                minimumSize: const Size(0, 32),
                                side: BorderSide(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                foregroundColor: AppColors.primary,
                              ),
                              child: const Text(
                                'Undo Skip',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 70 + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: Color(0xFFEDEAE6))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.home_outlined,
            label: 'HOME',
            isActive: false,
            onTap: () => Navigator.pushNamedAndRemoveUntil(
              context,
              '/home',
              (_) => false,
            ),
          ),
          _NavItem(
            icon: Icons.restaurant_menu_outlined,
            label: 'MENU',
            isActive: false,
            onTap: () => Navigator.pushNamedAndRemoveUntil(
              context,
              '/meal-booking',
              (_) => false,
            ),
          ),
          _NavItem(
            icon: Icons.confirmation_number_outlined,
            label: 'TOKEN',
            isActive: false,
            onTap: () => Navigator.pushNamed(context, '/meal-pass'),
          ),
          _NavItem(
            icon: Icons.history,
            label: 'HISTORY',
            isActive: true,
            onTap: () {},
          ),
          _NavItem(
            icon: Icons.person_outline,
            label: 'PROFILE',
            isActive: false,
            onTap: () => Navigator.pushNamed(context, '/profile'),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isActive ? AppColors.primary : AppColors.textDisabled,
            size: 26,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isActive ? AppColors.primary : AppColors.textDisabled,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
