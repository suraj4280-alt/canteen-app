import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'meal_state.dart';
import 'services/api_service.dart';

class FeedbackScreen extends StatefulWidget {
  final int? targetBookingId;
  const FeedbackScreen({super.key, this.targetBookingId});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackSlot {
  final String dateKey; // YYYY-MM-DD
  final String displayDate;
  final String slot; // Breakfast, Lunch...
  final List<String> items;
  final int? bookingId;
  bool isScanned;
  bool hasFeedback;
  int foodRating;
  int serviceRating;
  int cleanlinessRating;
  String comment;

  _FeedbackSlot({
    required this.dateKey,
    required this.displayDate,
    required this.slot,
    required this.items,
    this.bookingId,
    this.isScanned = false,
    this.hasFeedback = false,
    this.foodRating = 0,
    this.serviceRating = 0,
    this.cleanlinessRating = 0,
    this.comment = '',
  });
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  bool _isLoading = true;
  List<_FeedbackSlot> _slots = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    MealStateProvider.instance.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    MealStateProvider.instance.removeListener(_onStateChanged);
    super.dispose();
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

  Future<void> _loadData() async {
    try {
      // Load bookings that have been consumed (status = used) to show for feedback
      final historyData = await ApiService.getBookingHistory(page: 1, size: 50);
      final bookingItems = historyData['items'] as List<dynamic>;

      // Load existing feedback to mark which ones already have feedback
      final existingFeedback = await ApiService.getFeedback();
      final feedbackBookingIds = <int>{};
      for (final fb in existingFeedback) {
        if (fb['booking_id'] != null) {
          feedbackBookingIds.add(fb['booking_id'] as int);
        }
      }

      final List<_FeedbackSlot> loaded = [];
      for (final item in bookingItems) {
        final statusName = item['status_name']?.toString() ?? '';
        // Only show consumed (used) bookings for feedback
        if (statusName != 'used') continue;

        final bookingId = item['id'] as int? ?? 0;
        
        // If a targetBookingId is provided, ONLY show that specific booking
        if (widget.targetBookingId != null && bookingId != widget.targetBookingId) {
          continue;
        }

        final dateStr = item['date']?.toString() ?? '';
        final slotName = item['slot_name']?.toString() ?? 'Meal';
        final hasFeedback = feedbackBookingIds.contains(bookingId);

        // Find existing feedback ratings if available
        int foodRating = 0, serviceRating = 0, cleanlinessRating = 0;
        String comment = '';
        if (hasFeedback) {
          for (final fb in existingFeedback) {
            if (fb['booking_id'] == bookingId) {
              foodRating = fb['food_rating'] as int? ?? 0;
              serviceRating = fb['service_rating'] as int? ?? 0;
              cleanlinessRating = fb['cleanliness_rating'] as int? ?? 0;
              comment = fb['comment']?.toString() ?? '';
              break;
            }
          }
        }

        loaded.add(_FeedbackSlot(
          dateKey: dateStr,
          displayDate: _formatDisplayDate(dateStr),
          slot: slotName,
          items: [],
          bookingId: bookingId,
          isScanned: true, // used bookings are always scanned
          hasFeedback: hasFeedback,
          foodRating: foodRating,
          serviceRating: serviceRating,
          cleanlinessRating: cleanlinessRating,
          comment: comment,
        ));
      }

      loaded.sort((a, b) => b.dateKey.compareTo(a.dateKey));

      if (mounted) {
        setState(() {
          _slots = loaded;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitFeedback(
    _FeedbackSlot slot,
    int food,
    int service,
    int clean,
    String comment,
  ) async {
    if (slot.bookingId == null) return;
    try {
      final response = await ApiService.submitFeedback(
        bookingId: slot.bookingId!,
        foodRating: food,
        serviceRating: service,
        cleanlinessRating: clean,
        comment: comment.isNotEmpty ? comment : null,
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Thank you for your feedback! 🙏'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
        _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to submit feedback'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildTopBar(context),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _slots.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Text(
                        widget.targetBookingId != null
                            ? 'Feedback is locked.\n\nYou must scan your QR token at the canteen and collect your meal before you can leave feedback.'
                            : 'No completed meals found. You can only leave feedback after collecting your meal.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _slots.length,
                    itemBuilder: (ctx, idx) => _buildSlotCard(_slots[idx]),
                  ),
          ),
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
            'Meal Feedback',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(_FeedbackSlot slot) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.slot,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      slot.displayDate,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (slot.hasFeedback)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'SUBMITTED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Items: ${slot.items.join(', ')}',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFEDEAE6)),
          const SizedBox(height: 16),
          if (slot.hasFeedback)
            _buildReadonlyFeedback(slot)
          else if (!slot.isScanned)
            _buildLockedFeedback()
          else
            _FeedbackForm(
              slot: slot,
              onSubmit: (f, s, c, text) => _submitFeedback(slot, f, s, c, text),
            ),
        ],
      ),
    );
  }

  Widget _buildLockedFeedback() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: const [
          Icon(Icons.info_outline, color: AppColors.textMuted, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Feedback unlocks after meal collection is verified via QR scan.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadonlyFeedback(_FeedbackSlot slot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReadonlyRating('Food Quality', slot.foodRating),
        const SizedBox(height: 8),
        _buildReadonlyRating('Service', slot.serviceRating),
        const SizedBox(height: 8),
        _buildReadonlyRating('Cleanliness', slot.cleanlinessRating),
        if (slot.comment.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.inputBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '"${slot.comment}"',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textDark,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReadonlyRating(String label, int rating) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        Row(
          children: List.generate(
            5,
            (i) => Icon(
              i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
              color: i < rating ? AppColors.primary : const Color(0xFFD6D3CE),
              size: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedbackForm extends StatefulWidget {
  final _FeedbackSlot slot;
  final Function(int, int, int, String) onSubmit;

  const _FeedbackForm({required this.slot, required this.onSubmit});

  @override
  State<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<_FeedbackForm> {
  int _foodRating = 0;
  int _serviceRating = 0;
  int _cleanlinessRating = 0;
  final _commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildRatingRow(
          'Food Quality',
          _foodRating,
          (v) => setState(() => _foodRating = v),
        ),
        const SizedBox(height: 12),
        _buildRatingRow(
          'Service',
          _serviceRating,
          (v) => setState(() => _serviceRating = v),
        ),
        const SizedBox(height: 12),
        _buildRatingRow(
          'Cleanliness',
          _cleanlinessRating,
          (v) => setState(() => _cleanlinessRating = v),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _commentController,
          maxLines: 2,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Add a comment (optional)',
            hintStyle: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
            filled: true,
            fillColor: AppColors.inputBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              elevation: 0,
            ),
            onPressed:
                (_foodRating > 0 ||
                    _serviceRating > 0 ||
                    _cleanlinessRating > 0)
                ? () => widget.onSubmit(
                    _foodRating,
                    _serviceRating,
                    _cleanlinessRating,
                    _commentController.text,
                  )
                : null,
            child: const Text(
              'Submit Review',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRatingRow(
    String label,
    int rating,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        Row(
          children: List.generate(
            5,
            (i) => GestureDetector(
              onTap: () => onChanged(i + 1),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: i < rating
                      ? AppColors.primary
                      : const Color(0xFFD6D3CE),
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
