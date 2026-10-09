import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../database_helper.dart';
import 'connectivity_utils.dart';

class RequiredProfileRule {
  final String label;
  final List<String> keys;
  const RequiredProfileRule(this.label, this.keys);
}

const List<String> learnerLocationFieldKeys = [
  'Province',
  'District',
  'Municipality',
];

const List<RequiredProfileRule> learnerClockInRequiredProfileRules = [
  RequiredProfileRule('Title', ['Title']),
  RequiredProfileRule('Name', ['Name']),
  RequiredProfileRule('Surname', ['Surname']),
  RequiredProfileRule('ID Number', ['IDNumber']),
  RequiredProfileRule('Race', ['Race']),
  RequiredProfileRule('Language', ['Language']),
  RequiredProfileRule('Disability', ['Disability']),
  RequiredProfileRule('Cellphone Number', ['CellphoneNumber', 'PhoneNumber']),
  RequiredProfileRule('Email', ['Email']),
  RequiredProfileRule('Address Line 1', ['AddressLine1']),
  RequiredProfileRule('Address Line 2', ['AddressLine2']),
  RequiredProfileRule('Address Line 3', ['AddressLine3']),
  RequiredProfileRule('Postal Code', ['PostalCode']),
  RequiredProfileRule('Province', ['Province']),
  RequiredProfileRule('District', ['District']),
  RequiredProfileRule('Municipality', ['Municipality']),
  RequiredProfileRule('Next of Kin Name', ['KinName']),
  RequiredProfileRule('Next of Kin Relation', ['KinRelation']),
  RequiredProfileRule('Next of Kin Contact', ['KinContact']),
  RequiredProfileRule('School Name', ['SchoolName']),
  RequiredProfileRule('School Completion', ['SchoolCompletion']),
  RequiredProfileRule('School Location', ['SchoolLocation']),
  RequiredProfileRule('School Grade', ['SchoolGrade']),
  RequiredProfileRule('Profile Image', ['profile_image']),
  RequiredProfileRule('Learner Signature', ['signature']),
];

const List<String> learnerClockInRequiredDocuments = [
  'ID Document',
  'Qualifications',
  'Proof of Residence',
];

bool learnerProfileIsMissingValue(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  return normalized.isEmpty ||
      normalized == 'null' ||
      normalized == 'n/a' ||
      normalized == 'na' ||
      normalized == '-' ||
      normalized == 'unknown' ||
      normalized.startsWith('1900-01-01');
}

bool learnerProfileIsRuleMissing(
  Map<String, dynamic> learner,
  List<String> keys,
) {
  for (final key in keys) {
    if (!learnerProfileIsMissingValue(learner[key])) {
      return false;
    }
  }
  return true;
}

String learnerProfileResolveBestFieldKey(
  Map<String, dynamic> learner,
  List<String> keys,
) {
  for (final key in keys) {
    if (learner.containsKey(key)) {
      return key;
    }
  }
  return keys.first;
}

void _appendMissingLocationKeysIfNeeded(
  Map<String, dynamic> learner,
  List<String> missingKeys,
) {
  final anyLocationMissing = learnerLocationFieldKeys.any(
    (key) => learnerProfileIsMissingValue(learner[key]),
  );
  if (!anyLocationMissing) return;
  for (final key in learnerLocationFieldKeys) {
    if (!missingKeys.contains(key)) {
      missingKeys.add(key);
    }
  }
}

List<String> learnerProfileMissingFieldLabels(Map<String, dynamic> learner) {
  final missing = <String>[];
  for (final rule in learnerClockInRequiredProfileRules) {
    if (learnerProfileIsRuleMissing(learner, rule.keys)) {
      missing.add(rule.label);
    }
  }
  if (learnerLocationFieldKeys
      .any((key) => learnerProfileIsMissingValue(learner[key]))) {
    for (final rule in learnerClockInRequiredProfileRules) {
      if (learnerLocationFieldKeys.contains(rule.keys.first) &&
          !missing.contains(rule.label)) {
        missing.add(rule.label);
      }
    }
  }
  return missing;
}

List<String> learnerProfileMissingFieldKeys(Map<String, dynamic> learner) {
  final missingKeys = <String>[];
  for (final rule in learnerClockInRequiredProfileRules) {
    if (!learnerProfileIsRuleMissing(learner, rule.keys)) continue;
    missingKeys.add(learnerProfileResolveBestFieldKey(learner, rule.keys));
  }
  _appendMissingLocationKeysIfNeeded(learner, missingKeys);
  return missingKeys;
}

Map<String, dynamic> mergeLearnerPreferLocal(
  Map<String, dynamic> local,
  Map<String, dynamic> server,
) {
  final merged = Map<String, dynamic>.from(server);
  const preserveIfLocalHasData = [
    ...learnerLocationFieldKeys,
    'Title',
    'Name',
    'Surname',
    'IDNumber',
    'Race',
    'Language',
    'Disability',
    'CellphoneNumber',
    'PhoneNumber',
    'Email',
    'AddressLine1',
    'AddressLine2',
    'AddressLine3',
    'PostalCode',
    'KinName',
    'KinRelation',
    'KinContact',
    'SchoolName',
    'SchoolCompletion',
    'SchoolLocation',
    'SchoolGrade',
    'profile_image',
    'signature',
  ];

  for (final key in preserveIfLocalHasData) {
    final localValue = local[key];
    final serverValue = server[key];
    if (!learnerProfileIsMissingValue(localValue) &&
        learnerProfileIsMissingValue(serverValue)) {
      merged[key] = localValue;
    }
  }

  if (local['synced'] == 0) {
    for (final entry in local.entries) {
      if (!learnerProfileIsMissingValue(entry.value) &&
          learnerProfileIsMissingValue(merged[entry.key])) {
        merged[entry.key] = entry.value;
      }
    }
    merged['synced'] = 0;
  } else {
    merged['synced'] = 1;
  }
  return merged;
}

/// Local-first; refreshes from server when online unless local edits are unsynced.
Future<Map<String, dynamic>?> fetchLearnerForClockInValidation(
  String learnerId,
) async {
  final dbHelper = DatabaseHelper();
  final localLearner = await dbHelper.getLearnerById(learnerId);
  final hasUnsynced = localLearner != null && localLearner['synced'] == 0;

  if (hasUnsynced) {
    return localLearner;
  }

  if (!await hasNetworkConnectivity()) {
    return localLearner;
  }

  try {
    final response = await http
        .get(
          Uri.parse(
            '${AppConfig.learnerDetailsUrl}?LearnerID=${Uri.encodeQueryComponent(learnerId)}',
          ),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      return localLearner;
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map ||
        decoded['success'] != true ||
        decoded['data'] == null) {
      return localLearner;
    }

    final serverLearner = Map<String, dynamic>.from(decoded['data']);
    final merged = localLearner == null
        ? serverLearner
        : mergeLearnerPreferLocal(localLearner, serverLearner);

    await dbHelper.upsertLearner(merged);
    return merged;
  } catch (_) {
    return localLearner;
  }
}
