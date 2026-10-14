import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/features/reports/data/report_repository.dart';

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(),
);
