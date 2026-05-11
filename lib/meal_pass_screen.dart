import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_colors.dart';
import 'services/api_service.dart';

import 'feedback_screen.dart';

class MealPassScreen extends StatefulWidget {
  final String? studentName;
  final String? roomNumber;
  final String? orderID;
  final int? bookingId;
  final String? bookedDate;
  final String? location;
  final List<String>? bookedSlots;
  final Map<String, List<String>>? slotItems;
  final bool isCompleted;

  const MealPassScreen({
    super.key,
    this.studentName,
    this.roomNumber,
    this.orderID,
    this.bookingId,
    this.bookedDate,
    this.location,
    this.bookedSlots,
    this.slotItems,
    this.isCompleted = false,
  });

  @override
  State<MealPassScreen> createState() => _MealPassScreenState();
}

class _MealPassScreenState extends State<MealPassScreen> {
  String _studentName = '';
  bool _isLoading = true;
  Timer? _timer;

  String? _qrPayload;
  bool _isLoadingQr = true;
  String? _qrError;

  @override
  void initState() {
    super.initState();
    _loadData();
    _fetchQrData();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _fetchQrData() async {
    int? bookingId = _localBookingId;
    if (bookingId == null && _localOrderId != null) {
      bookingId = int.tryParse(_localOrderId!.replaceAll(RegExp(r'[^0-9]'), ''));
    }
    if (bookingId == null || bookingId == 0) {
      if (mounted) {
        setState(() {
          _qrError = 'No booking ID available';
          _isLoadingQr = false;
        });
      }
      return;
    }
    
    try {
      final response = await ApiService.getBookingQR(bookingId);
      if (mounted) {
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            _qrPayload = data['qr_token'];
            _qrError = null;
            _isLoadingQr = false;
          });
        } else {
          final data = jsonDecode(response.body);
          setState(() {
            _qrError = data['detail'] ?? 'QR not available';
            _isLoadingQr = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _qrError = 'Network error fetching QR';
          _isLoadingQr = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int? _localBookingId;
  String? _localDate;
  String? _localLocation;
  String? _localOrderId;
  String? _localMealName;
  List<String>? _localItems;
  bool _localIsCompleted = false;

  Future<void> _loadData() async {
    final user = ApiService.currentUser;
    final fn = user?['firstName']?.toString() ?? '';
    final ln = user?['lastName']?.toString() ?? '';

    _studentName = '$fn $ln'.trim();
    if (_studentName.isEmpty) _studentName = widget.studentName ?? 'Student';

    // If we have explicit widget parameters, use them
    _localBookingId = widget.bookingId;
    _localDate = widget.bookedDate;
    _localLocation = widget.location;
    _localOrderId = widget.orderID;
    _localIsCompleted = widget.isCompleted;
    if (widget.bookedSlots != null && widget.bookedSlots!.isNotEmpty) {
      _localMealName = widget.bookedSlots!.first;
      if (widget.slotItems != null && widget.slotItems!.containsKey(_localMealName)) {
        _localItems = widget.slotItems![_localMealName];
      }
    }

    // If no booking ID was provided (e.g. pushed from generic navbar), fetch the active one
    if (_localBookingId == null) {
      try {
        final upcoming = await ApiService.getUpcomingBookings();
        if (upcoming.isNotEmpty) {
          final todayStr = DateTime.now().toIso8601String().substring(0, 10);
          
          // Helper to find current slot
          final now = DateTime.now();
          final totalMinutes = now.hour * 60 + now.minute;
          String? activeSlotName;
          
          // First pass: look for exact current time match
          for (final b in upcoming) {
            final startStr = b['start_time']?.toString() ?? '';
            final endStr = b['end_time']?.toString() ?? '';
            if (startStr.length >= 5 && endStr.length >= 5) {
              final start = int.parse(startStr.split(':')[0]) * 60 + int.parse(startStr.split(':')[1]);
              final end = int.parse(endStr.split(':')[0]) * 60 + int.parse(endStr.split(':')[1]);
              if (totalMinutes >= start && totalMinutes <= end && b['date']?.toString() == todayStr) {
                activeSlotName = b['slot_name']?.toString();
                break;
              }
            }
          }
          
          // Second pass: just grab the very next upcoming meal today
          if (activeSlotName == null) {
             for (final b in upcoming) {
                if (b['date']?.toString() == todayStr) {
                   activeSlotName = b['slot_name']?.toString();
                   break;
                }
             }
          }

          // Pick the active or first upcoming booking
          Map<String, dynamic>? targetBooking;
          for (final b in upcoming) {
            if (b['date']?.toString() == todayStr && b['slot_name']?.toString() == activeSlotName) {
              targetBooking = b;
              break;
            }
          }

          if (targetBooking != null) {
            _localBookingId = targetBooking['id'] as int?;
            _localDate = targetBooking['date']?.toString();
            _localLocation = 'Hostel ${user?['hostel'] ?? '---'}';
            _localOrderId = targetBooking['order_id']?.toString();
            _localMealName = targetBooking['slot_name']?.toString();
            _localItems = [targetBooking['slot_name']?.toString() ?? 'Meal'];
            _localIsCompleted = targetBooking['status_name']?.toString() == 'used';
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      // Now fetch the QR data with our resolved ID
      _fetchQrData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildTopBar(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildPassCard(context),
                  const SizedBox(height: 16),
                  _buildMealDetails(),
                  const SizedBox(height: 16),
                  _buildActionsRow(context),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
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
                'My Meal Pass',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEDEAE6)),
            ),
            child: const Icon(
              Icons.share_outlined,
              color: AppColors.textMuted,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassCard(BuildContext context) {
    final mealName = widget.bookedSlots?.isNotEmpty == true ? widget.bookedSlots!.first : 'Meal';
    final roomName = widget.roomNumber ?? '---';
    final orderId = widget.orderID ?? '---';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'HOSTEL MESS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$mealName Pass',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const Icon(
                      Icons.restaurant,
                      color: Colors.white70,
                      size: 32,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: SizedBox(
                    width: 180,
                    height: 180,
                  child: _localIsCompleted
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check_circle_outline, color: AppColors.success, size: 64),
                            SizedBox(height: 12),
                            Text(
                              'QR Scanned',
                              style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        )
                      : _isLoadingQr
                          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                          : _qrError != null
                              ? Center(
                                  child: Text(
                                    _qrError!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                )
                              : QrImageView(
                                  data: _qrPayload ?? '',
                                  version: QrVersions.auto,
                                  backgroundColor: Colors.white,
                                ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _InfoChip(label: 'NAME', value: _studentName),
                      _InfoChip(label: 'ROOM', value: 'Room $roomName'),
                      _InfoChip(label: 'ORDER', value: orderId),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Show at counter
                Text(
                  _localIsCompleted ? 'Meal has been successfully collected' : 'Show this QR at the mess counter',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealDetails() {
    final mealName = _localMealName ?? 'Meal';
    final dateStr = _localDate ?? '---';
    final locationStr = _localLocation ?? '---';
    final itemsList = _localItems ?? <String>[];
    
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MEAL DETAILS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const Divider(height: 20, color: Color(0xFFF0EEEA)),
          _buildDetailRow('Meal Type', mealName),
          _buildDetailRow('Date', dateStr),
          _buildDetailRow('Location', locationStr),
          const Divider(height: 20, color: Color(0xFFF0EEEA)),
          const Text(
            'ITEMS SELECTED',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          _buildDetailRow(
            'Items',
            itemsList.isEmpty ? 'Standard Menu' : itemsList.join(', '),
          ),
          const Divider(height: 20, color: Color(0xFFF0EEEA)),
          const Text(
            'STATUS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _localIsCompleted ? AppColors.textDisabled : AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _localIsCompleted ? 'Completed — Meal collected' : 'Active — Ready to scan',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _localIsCompleted ? AppColors.textDisabled : AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.restaurant_menu_outlined,
            label: 'Book Meal',
            onTap: () => Navigator.pushNamed(context, '/meal-booking'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.star_border,
            label: 'Feedback',
            isDisabled: !_localIsCompleted,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FeedbackScreen(
                    targetBookingId: _localBookingId,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.history,
            label: 'History',
            onTap: () => Navigator.pushNamed(context, '/history'),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 70 + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: const Border(top: BorderSide(color: Color(0xFFEDEAE6))),
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
            onTap: () => Navigator.pushNamed(context, '/meal-booking'),
          ),
          _NavItem(
            icon: Icons.confirmation_number,
            label: 'TOKEN',
            isActive: true,
            onTap: () {},
          ),
          _NavItem(
            icon: Icons.history_outlined,
            label: 'HISTORY',
            isActive: false,
            onTap: () => Navigator.pushNamedAndRemoveUntil(
              context,
              '/history',
              (_) => false,
            ),
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

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white60,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDisabled;
  
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDisabled ? const Color(0xFFF9FAFB) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDisabled ? [] : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: isDisabled ? AppColors.textDisabled : AppColors.primary, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDisabled ? AppColors.textDisabled : AppColors.textMuted,
              ),
            ),
          ],
        ),
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
            size: 22,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isActive ? AppColors.primary : AppColors.textDisabled,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
