import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'config.dart';

/// Normalised API result — same contract the web admin's apiFetch() returns:
/// a JSON map that always carries `status` (true/false) and, on failure, `message`.
class ApiRes {
  ApiRes(this.json);
  final Map<String, dynamic> json;

  bool get ok => json['status'] == true;
  String get message => (json['message'] ?? '').toString();
  dynamic get data => json['data'];
  dynamic operator [](String key) => json[key];

  /// `data` as a list, also accepting `{data: {rows|items|data: [...]}}` shapes.
  List<Map<String, dynamic>> get list => asList(json['data']);

  /// `data` as a map (empty when missing).
  Map<String, dynamic> get map => asMap(json['data']);

  static List<Map<String, dynamic>> asList(dynamic v) {
    if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    if (v is Map) {
      for (final k in const ['rows', 'items', 'data', 'list', 'records', 'results']) {
        if (v[k] is List) return asList(v[k]);
      }
    }
    return const [];
  }

  static Map<String, dynamic> asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// Best-effort total row count across the paginated response shapes the API uses.
  int? get total {
    int? pick(dynamic v) => v == null ? null : int.tryParse(v.toString());
    final d = json['data'];
    return pick(json['total']) ??
        pick(json['totalCount']) ??
        pick(json['count']) ??
        pick(ApiRes.asMap(json['pagination'])['total']) ??
        pick(ApiRes.asMap(json['meta'])['total']) ??
        (d is Map ? (pick(d['total']) ?? pick(d['totalCount']) ?? pick(ApiRes.asMap(d['pagination'])['total'])) : null);
  }
}

/// Called when the server answers STEP_UP_REQUIRED; should ask the admin for
/// their password, POST /admin/security/step-up and return true on success.
typedef StepUpHandler = Future<bool> Function();

class Api {
  Api._();
  static final Api I = Api._();

  late Dio _dio;
  late PersistCookieJar _jar;
  StepUpHandler? stepUpHandler;
  Future<bool>? _stepUpInflight;

  /// Fired when a request comes back 401 so the app can return to login.
  void Function()? onUnauthorized;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _jar = PersistCookieJar(storage: FileStorage('${dir.path}/.cookies/'));
    _build();
  }

  /// Re-create the client after the server is switched.
  void _build() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      // Treat every HTTP status as a response; we normalise below like the web client.
      validateStatus: (_) => true,
      headers: {'Accept': 'application/json', 'X-Client-Platform': 'admin-mobile'},
    ));
    _dio.interceptors.add(CookieManager(_jar));
  }

  void rebuild() => _build();

  Future<void> clearCookies() => _jar.deleteAll();

  Future<bool> hasSessionCookie() async {
    final cookies = await _jar.loadForRequest(Uri.parse(AppConfig.baseUrl));
    return cookies.any((c) => c.name == 'efm_a_token');
  }

  Map<String, dynamic>? _cleanQuery(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      out[k] = v is bool ? v.toString() : v;
    });
    return out;
  }

  ApiRes _normalize(Response r) {
    final body = r.data;
    Map<String, dynamic> json;
    if (body is Map) {
      json = Map<String, dynamic>.from(body);
    } else if (body is List) {
      json = {'data': body};
    } else {
      json = {'raw': body};
    }
    final code = r.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      json['status'] = false;
      json['message'] ??= code == 401 ? 'Session expired. Please log in again.' : 'Request failed ($code)';
      json['httpStatus'] = code;
      if (code == 401) onUnauthorized?.call();
    } else {
      json['status'] ??= true;
    }
    return ApiRes(json);
  }

  ApiRes _networkError(Object e) {
    var msg = 'Unable to reach the server.';
    if (e is DioException && e.type == DioExceptionType.connectionTimeout) msg = 'Connection timed out.';
    if (e is SocketException) msg = 'No internet connection.';
    return ApiRes({'status': false, 'networkError': true, 'message': msg});
  }

  Future<ApiRes> _send(Future<Response> Function() call) async {
    try {
      var res = _normalize(await call());
      if (res['code'] == 'STEP_UP_REQUIRED' && stepUpHandler != null) {
        _stepUpInflight ??= stepUpHandler!().whenComplete(() => _stepUpInflight = null);
        if (await _stepUpInflight!) res = _normalize(await call());
      }
      return res;
    } catch (e) {
      return _networkError(e);
    }
  }

  Future<ApiRes> get(String path, [Map<String, dynamic>? query]) =>
      _send(() => _dio.get(path, queryParameters: _cleanQuery(query)));

  Future<ApiRes> post(String path, [Object? body]) => _send(() => _dio.post(path, data: body ?? {}));

  Future<ApiRes> put(String path, [Object? body]) => _send(() => _dio.put(path, data: body ?? {}));

  Future<ApiRes> patch(String path, [Object? body]) => _send(() => _dio.patch(path, data: body ?? {}));

  Future<ApiRes> delete(String path, [Object? body]) => _send(() => _dio.delete(path, data: body));

  /// Multipart upload. [files] maps field name → local file path.
  Future<ApiRes> upload(String path, {Map<String, String> files = const {}, Map<String, dynamic> fields = const {}, String method = 'POST'}) async {
    final form = FormData();
    fields.forEach((k, v) {
      if (v != null) form.fields.add(MapEntry(k, v.toString()));
    });
    for (final e in files.entries) {
      form.files.add(MapEntry(e.key, await MultipartFile.fromFile(e.value, filename: e.value.split(RegExp(r'[\\/]')).last)));
    }
    return _send(() => _dio.request(path, data: form, options: Options(method: method)));
  }

  /// Raw bytes download (PDF invoices, exports).
  Future<List<int>?> download(String path, [Map<String, dynamic>? query]) async {
    try {
      final r = await _dio.get<List<int>>(path, queryParameters: _cleanQuery(query), options: Options(responseType: ResponseType.bytes));
      if ((r.statusCode ?? 500) >= 300) return null;
      return r.data;
    } catch (_) {
      return null;
    }
  }
}

/// Shorthand used throughout the screens.
Api get api => Api.I;
