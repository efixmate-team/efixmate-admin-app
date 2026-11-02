import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import 'theme.dart';
import 'widgets.dart';

typedef PageFetcher = Future<ApiRes> Function(int page, int limit, String search);

/// Infinite-scroll list over any paginated admin endpoint, with optional
/// search box and a header slot for filters. Call [PagedListState.reload]
/// through a GlobalKey after a mutation.
class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.header,
    this.searchHint,
    this.limit = 20,
    this.empty = 'Nothing here yet',
    this.extract,
  });

  final PageFetcher fetch;
  final Widget Function(BuildContext context, Map<String, dynamic> row, int index) itemBuilder;
  final Widget? header;

  /// Shows a search box when non-null.
  final String? searchHint;
  final int limit;
  final String empty;

  /// Custom row extraction when the list isn't under `data`.
  final List<Map<String, dynamic>> Function(ApiRes res)? extract;

  @override
  State<PagedList> createState() => PagedListState();
}

class PagedListState extends State<PagedList> {
  final _rows = <Map<String, dynamic>>[];
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  int _page = 1;
  int? _total;
  bool _loading = false;
  bool _done = false;
  String? _error;
  int _gen = 0;

  List<Map<String, dynamic>> get rows => _rows;
  int? get total => _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _more();
    });
    reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    _gen++;
    _page = 1;
    _done = false;
    _error = null;
    _loading = false;
    setState(() {
      _rows.clear();
      _total = null;
    });
    await _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    final gen = _gen;
    setState(() => _loading = true);
    final res = await widget.fetch(_page, widget.limit, _search.text.trim());
    if (!mounted || gen != _gen) return;
    setState(() {
      _loading = false;
      if (!res.ok) {
        _error = res.message.isEmpty ? 'Could not load' : res.message;
        _done = true;
        return;
      }
      final got = widget.extract?.call(res) ?? res.list;
      _rows.addAll(got);
      _total = res.total ?? _total;
      _page++;
      if (got.length < widget.limit || (_total != null && _rows.length >= _total!)) _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (widget.searchHint != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () {
                      _search.clear();
                      reload();
                    }),
            ),
            onChanged: (_) {
              setState(() {});
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 450), reload);
            },
          ),
        ),
      if (widget.header != null) widget.header!,
      if (_total != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Align(alignment: Alignment.centerLeft, child: Text('$_total results', style: const TextStyle(color: C.muted, fontSize: 12))),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: reload,
          child: _rows.isEmpty && !_loading
              ? ListView(children: [
                  const SizedBox(height: 60),
                  _error != null ? ErrorView(_error!, onRetry: reload) : EmptyView(widget.empty),
                ])
              : ListView.separated(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                  itemCount: _rows.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (c, i) {
                    if (i == _rows.length) {
                      return _loading
                          ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                          : const SizedBox(height: 8);
                    }
                    return widget.itemBuilder(c, _rows[i], i);
                  },
                ),
        ),
      ),
    ]);
  }
}
