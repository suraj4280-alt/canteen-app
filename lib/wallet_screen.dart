import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'services/api_service.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Map<String, dynamic>? _wallet;
  List<dynamic> _transactions = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _filter = 'all'; // all, debit, credit, refund, recharge
  int _page = 1;
  int _total = 0;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wallet = await ApiService.getWalletBalance();
      final txnFilter = _filter == 'all' ? null : _filter;
      final txnData = await ApiService.getWalletTransactions(
        page: 1,
        size: _pageSize,
        type: txnFilter,
      );
      if (mounted) {
        setState(() {
          _wallet = wallet;
          _transactions = txnData['items'] as List<dynamic>;
          _total = txnData['total'] as int;
          _page = 1;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _transactions.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final txnFilter = _filter == 'all' ? null : _filter;
      final txnData = await ApiService.getWalletTransactions(
        page: _page + 1,
        size: _pageSize,
        type: txnFilter,
      );
      if (mounted) {
        setState(() {
          _transactions.addAll(txnData['items'] as List<dynamic>);
          _page++;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _setFilter(String filter) {
    if (_filter == filter) return;
    _filter = filter;
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7F4),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _buildContent(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 24,
        right: 24,
        bottom: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white70, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'My Wallet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet,
                        color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Prepaid',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Balance card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F3460), Color(0xFF533483)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available Balance',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '\u20b9${(_wallet?['current_balance'] ?? 0).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildBalanceInfo(
                      'Semester Total',
                      '\u20b9${(_wallet?['semester_balance'] ?? 0).toStringAsFixed(0)}',
                    ),
                    _buildBalanceInfo(
                      'Transactions',
                      '$_total',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.5),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (scrollInfo.metrics.pixels >
                scrollInfo.metrics.maxScrollExtent - 200 &&
            !_loadingMore) {
          _loadMore();
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          // Filter chips
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildFilterChip('All', 'all'),
                _buildFilterChip('Debits', 'debit'),
                _buildFilterChip('Credits', 'credit'),
                _buildFilterChip('Refunds', 'refund'),
                _buildFilterChip('Recharges', 'recharge'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Transaction header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Transaction History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                '$_total transactions',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_transactions.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.receipt_long, size: 48,
                      color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  const Text(
                    'No transactions yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ..._transactions.map((txn) => _buildTransactionCard(txn)),
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isActive = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _setFilter(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isActive
                  ? AppColors.primary
                  : const Color(0xFFE5E7EB),
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(dynamic txn) {
    final type = txn['transaction_type'] as String;
    final amount = (txn['amount'] as num).toDouble();
    final balanceAfter = (txn['balance_after'] as num).toDouble();
    final description = txn['description'] as String? ?? '';
    final orderId = txn['order_id'] as String?;
    final slotName = txn['slot_name'] as String?;
    final createdAt = txn['created_at'] as String? ?? '';

    final isDebit = type == 'debit';
    final isRefund = type == 'refund';
    final isRecharge = type == 'recharge';

    IconData icon;
    Color iconColor;
    Color bgColor;
    String prefix;

    if (isDebit) {
      icon = Icons.restaurant;
      iconColor = const Color(0xFFDC2626);
      bgColor = const Color(0xFFFEF2F2);
      prefix = '-';
    } else if (isRefund) {
      icon = Icons.replay;
      iconColor = const Color(0xFF2563EB);
      bgColor = const Color(0xFFEFF6FF);
      prefix = '+';
    } else if (isRecharge) {
      icon = Icons.add_circle_outline;
      iconColor = const Color(0xFF16A34A);
      bgColor = const Color(0xFFF0FDF4);
      prefix = '+';
    } else {
      icon = Icons.swap_horiz;
      iconColor = const Color(0xFF16A34A);
      bgColor = const Color(0xFFF0FDF4);
      prefix = '+';
    }

    // Format date
    String dateStr = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt);
        const months = [
          'Jan','Feb','Mar','Apr','May','Jun',
          'Jul','Aug','Sep','Oct','Nov','Dec'
        ];
        final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
        final ampm = dt.hour >= 12 ? 'PM' : 'AM';
        dateStr =
            '${dt.day} ${months[dt.month - 1]} · $h:${dt.minute.toString().padLeft(2, '0')} $ampm';
      } catch (_) {
        dateStr = createdAt;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slotName != null
                      ? '$slotName${orderId != null ? ' · $orderId' : ''}'
                      : description,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$prefix\u20b9${amount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDebit ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Bal: \u20b9${balanceAfter.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
