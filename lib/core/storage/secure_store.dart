import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens and passwords never touch prefs, logs or crash reports.
/// Windows → Credential Manager, Android → Keystore-backed storage.
///
/// v1.0.22：读失败不再静默返回 null 就完事。
/// Android 的加密存储一旦密钥失效（恢复备份 / 换机恢复 / 系统重置），
/// `read` 会持续抛异常——此时必须把坏条目删掉重写，否则用户会陷入
/// 「登录成功 → 重启又掉线」的死循环，且日志里什么都没有。
class SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    wOptions: WindowsOptions(),
  );

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (error) {
      debugPrint('secure: read failed for $key ($error), purging entry');
      await _purge(key);
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (error) {
      debugPrint('secure: write failed for $key ($error), retrying after purge');
      // 写入失败通常也是同一个坏条目挡路：清掉再写一次
      await _purge(key);
      try {
        await _storage.write(key: key, value: value);
      } catch (retryError) {
        // 仍失败就让会话不跨重启，不影响当前浏览
        debugPrint('secure: write retry failed for $key ($retryError)');
      }
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (error) {
      debugPrint('secure: delete failed for $key ($error)');
    }
  }

  Future<bool> has(String key) async => (await read(key))?.isNotEmpty == true;

  Future<void> _purge(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // 连删除都失败就只能放弃，调用方会拿到 null 并走重新登录
    }
  }
}
