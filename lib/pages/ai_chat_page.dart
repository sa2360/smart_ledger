import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/bill.dart';
import '../services/bill_qa_service.dart';
import '../services/settings_service.dart';

class _ChatMsg {
  final String role; // user / assistant
  final String content;
  _ChatMsg(this.role, this.content);
}

/// AI 记账助手：基于账单数据的多轮对话查询与分析
class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMsg> _messages = [];
  List<String> _billLines = [];
  bool _loading = false;

  static const _quickQuestions = [
    '我这个月总共花了多少？',
    '哪个分类花得最多？',
    '帮我看看奶茶花了多少',
    '这个月和上个月比，支出变化大吗？',
  ];

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBills() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final lastMonth = now.month == 1
        ? '${now.year - 1}-12'
        : '${now.year}-${(now.month - 1).toString().padLeft(2, '0')}';
    final thisMonth =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final bills = [
      ...await db.queryBills(month: lastMonth),
      ...await db.queryBills(month: thisMonth),
    ];
    if (!mounted) return;
    setState(() {
      _billLines = bills.map(_lineOf).toList();
    });
  }

  static String _lineOf(Bill b) =>
      '${b.createTime} | ${b.isExpense ? "支出" : "收入"} | ${b.category} '
      '| ${b.money.toStringAsFixed(2)}元 | ${b.remark}';

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _loading) return;
    if (!SettingsService.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('AI 服务未就绪，请到「我的」页开启内置模型或配置自定义模型'),
          behavior: SnackBarBehavior.floating));
      return;
    }
    _ctrl.clear();
    setState(() {
      _messages.add(_ChatMsg('user', question));
      _loading = true;
    });
    _scrollToBottom();

    try {
      // 多轮上下文：最多带最近 8 条历史消息
      final history = _messages
          .take(_messages.length - 1)
          .toList()
          .reversed
          .take(8)
          .toList()
          .reversed
          .map((m) => (role: m.role, content: m.content))
          .toList();
      final reply = await BillQaService.answer(
          question: question, history: history, billLines: _billLines);
      setState(() {
        _messages.add(_ChatMsg('assistant', reply));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add(_ChatMsg('assistant', '出错了：$e'));
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('AI 记账助手',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _emptyView()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length) return _typingBubble();
                      return _bubble(_messages[i]);
                    },
                  ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _emptyView() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 30),
          Icon(Icons.forum, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Center(
            child: Text('问我任何关于账单的问题',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('我会基于你最近两个月的真实账单回答',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _quickQuestions
                .map((q) => ActionChip(
                      label: Text(q, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _send(q),
                    ))
                .toList(),
          ),
        ],
      );

  Widget _bubble(_ChatMsg m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF1E88E5) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: SelectableText(
          m.content,
          style: TextStyle(
              fontSize: 14, height: 1.5, color: isUser ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  Widget _typingBubble() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );

  Widget _inputBar() => Container(
        padding: EdgeInsets.fromLTRB(
            12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: '例如：我这个月奶茶花了多少？',
                  filled: true,
                  fillColor: const Color(0xFFF8F9FB),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _loading ? null : () => _send(_ctrl.text),
              style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1E88E5)),
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ],
        ),
      );
}
