import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const macOsDevelopmentSecureStorageAccountName =
    'bnbu.macos.development.secure-storage';
const macOsReleaseSecureStorageAccountName = String.fromEnvironment(
  'MACOS_RELEASE_SECURE_STORAGE_ACCOUNT',
  defaultValue: 'invalid.local.bnbu.macos.release.secure-storage',
);
const macOsLegacyReleaseSecureStorageAccountName =
    AppleOptions.defaultAccountName;

const macOsSecureStorageAccountName = kReleaseMode
    ? macOsReleaseSecureStorageAccountName
    : macOsDevelopmentSecureStorageAccountName;

const macOsSecureStorageOptions = MacOsOptions(
  accountName: macOsSecureStorageAccountName,
  usesDataProtectionKeychain: false,
);

const macOsLegacyReleaseSecureStorageOptions = MacOsOptions(
  accountName: macOsLegacyReleaseSecureStorageAccountName,
  usesDataProtectionKeychain: false,
);
