// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

abstract interface class CacheStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value, Duration ttl);
  Future<void> delete(String key);
  Future<void> clear();
  Future<void> gc();
}
