import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class ApiService {
  static const Duration timeout = Duration(seconds: 15);

  String baseUrl;
  http.Client _client;

  ApiService({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  String _u(String path) {
    final b = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return b + path.replaceFirst(RegExp(r'^/+'), '');
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.endsWith('/') ? url : '$url/';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', baseUrl);
  }

  static Future<String> getSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('server_url') ?? 'http://192.168.18.240:8000';
  }

  Future<Map<String, dynamic>> health() async {
    final res = await _client.get(Uri.parse(_u('health'))).timeout(timeout);
    return json.decode(res.body);
  }

  String _detail(http.Response res) {
    try {
      final body = json.decode(res.body);
      if (body is Map && body['detail'] != null) return body['detail'].toString();
    } catch (_) {}
    return 'HTTP ${res.statusCode}';
  }

  Future<Product?> getProduct(String barcode) async {
    final res = await _client
        .get(Uri.parse(_u('products/${Uri.encodeComponent(barcode)}')))
        .timeout(timeout);
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) throw Exception('Gagal ambil produk: ${_detail(res)}');
    return Product.fromJson(json.decode(res.body));
  }

  Future<List<Product>> listProducts({String? search, bool missingPrice = false}) async {
    final q = <String, String>{};
    if (search != null && search.isNotEmpty) q['search'] = search;
    if (missingPrice) q['missing_price'] = 'true';
    final uri = Uri.parse(_u('products')).replace(queryParameters: q);
    final res = await _client.get(uri).timeout(timeout);
    if (res.statusCode >= 400) throw Exception('Gagal daftar produk: ${_detail(res)}');
    final list = json.decode(res.body) as List;
    return list.map((e) => Product.fromJson(e)).toList();
  }

  Future<Product> createProduct(String barcode, {String? name, int? price}) async {
    final res = await _client.post(
      Uri.parse(_u('products')),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'barcode': barcode, 'name': name, 'price': price}),
    ).timeout(timeout);
    if (res.statusCode >= 400) throw Exception('Gagal tambah produk: ${_detail(res)}');
    return Product.fromJson(json.decode(res.body));
  }

  Future<Product> updateProduct(String barcode, {String? name, int? price}) async {
    final res = await _client.put(
      Uri.parse(_u('products/${Uri.encodeComponent(barcode)}')),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name, 'price': price}),
    ).timeout(timeout);
    if (res.statusCode >= 400) throw Exception('Gagal ubah produk: ${_detail(res)}');
    return Product.fromJson(json.decode(res.body));
  }

  Future<void> deleteProduct(String barcode) async {
    final res = await _client
        .delete(Uri.parse(_u('products/${Uri.encodeComponent(barcode)}')))
        .timeout(timeout);
    if (res.statusCode >= 400) throw Exception('Gagal hapus produk: ${_detail(res)}');
  }

  Future<Map<String, dynamic>> importExcel(Uint8List bytes, String fileName) async {
    final req = http.MultipartRequest('POST', Uri.parse(_u('import/excel')));
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    final streamed = await req.send().timeout(timeout);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 400) throw Exception('Gagal import: ${resp.statusCode}');
    return json.decode(resp.body);
  }

  Future<SearchSuggestResult> searchSuggest({String? barcode, String? name}) async {
    final q = <String, String>{};
    if (barcode != null && barcode.isNotEmpty) q['barcode'] = barcode;
    if (name != null && name.isNotEmpty) q['name'] = name;
    final uri = Uri.parse(_u('search/suggest')).replace(queryParameters: q);
    final res = await _client.get(uri).timeout(timeout);
    if (res.statusCode >= 400) throw Exception('Gagal saran: ${_detail(res)}');
    final d = json.decode(res.body);
    return SearchSuggestResult(
      barcode: d['barcode'],
      name: d['name'],
      priceSuggestions: (d['price_suggestions'] as List? ?? [])
          .map((e) => PriceSuggestion(source: e['source'] ?? '', title: e['title'] ?? '', price: e['price'] ?? ''))
          .toList(),
      recommendedPrice: d['recommended_price'] is int ? d['recommended_price'] : int.tryParse(d['recommended_price']?.toString() ?? ''),
      cached: d['cached'] ?? false,
      source: d['source']?.toString(),
      estimated: d['estimated'] == true,
    );
  }

  Future<void> speak(String text) async {
    final res = await _client.post(
      Uri.parse(_u('speak')),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'text': text}),
    ).timeout(timeout);
    if (res.statusCode >= 400) throw Exception('Gagal bicara: ${_detail(res)}');
  }

  Future<void> announceItem(String name, int price) async {
    final res = await _client.post(
      Uri.parse(_u('announce/item')),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name, 'price': price}),
    ).timeout(timeout);
    if (res.statusCode >= 400) throw Exception('Gagal umumkan harga: ${_detail(res)}');
  }

  Future<Map<String, dynamic>> checkout(List<CartItem> items) async {
    final body = {
      'items': items.map((e) => {'barcode': e.barcode, 'qty': e.qty}).toList(),
    };
    final res = await _client.post(
      Uri.parse(_u('checkout')),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    ).timeout(timeout);
    if (res.statusCode >= 400) throw Exception('Gagal checkout: ${_detail(res)}');
    return json.decode(res.body);
  }

  Future<List<Transaction>> getTransactions({String? date}) async {
    final q = <String, String>{};
    if (date != null && date.isNotEmpty) q['date'] = date;
    final uri = Uri.parse(_u('transactions')).replace(queryParameters: q);
    final res = await _client.get(uri).timeout(timeout);
    if (res.statusCode >= 400) throw Exception('Gagal riwayat: ${res.statusCode}');
    final list = json.decode(res.body) as List;
    return list.map((e) => Transaction.fromJson(e)).toList();
  }

  void dispose() {
    _client.close();
  }
}
