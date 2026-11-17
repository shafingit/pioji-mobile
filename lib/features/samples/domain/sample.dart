import '../../../core/utils/json.dart';
import '../../../core/widgets/status_badge.dart';

enum SampleStatus {
  received('received', 'Received', Tone.success),
  pendingEvaluation('pending_evaluation', 'Pending evaluation', Tone.warning),
  evaluated('evaluated', 'Evaluated', Tone.accent),
  assignedToBuyers('assigned_to_buyers', 'Assigned', Tone.accent),
  approved('approved', 'Approved', Tone.success),
  unknown('', 'Unknown', Tone.neutral);

  const SampleStatus(this.api, this.label, this.tone);
  final String api;
  final String label;
  final Tone tone;

  static SampleStatus parse(Object? v) =>
      values.firstWhere((s) => s.api == v?.toString(), orElse: () => unknown);

  static const pickable = [received, pendingEvaluation, evaluated, assignedToBuyers, approved];
}

class Sample {
  const Sample({
    this.raw = const {},
    required this.id,
    this.arrivalDate,
    this.gardenId,
    this.gardenName,
    this.grade,
    this.invoicePrefix,
    this.invoiceNo,
    this.packages,
    this.weight,
    this.totalKgs,
    this.sampleType,
    this.status = SampleStatus.unknown,
    this.statusRaw,
    this.remarks,
    this.batchRef,
    this.forCompany,
    this.partyId,
    this.partyName,
    this.isParked = false,
    this.evaluationStatus,
    this.evaluatedAt,
    this.evaluatedBy,
    this.comments,
    this.overallScore,
    this.scores = const {},
  });

  /// The record as the API sent it, for fields read through [ExtraField]s.
  final Map<String, dynamic> raw;

  /// Tasting score fields, in the order they're shown (0–10 each).
  static const scoreFields = {
    'appearance_score': 'Appearance',
    'aroma_score': 'Aroma',
    'liquor_score': 'Liquor',
    'color_score': 'Colour',
    'taste_score': 'Taste',
    'strength_score': 'Strength',
    'briskness_score': 'Briskness',
  };

  final int id;
  final DateTime? arrivalDate;
  final int? gardenId;
  final String? gardenName;
  final String? grade;
  final String? invoicePrefix;
  final String? invoiceNo;
  final int? packages;
  final double? weight;
  final double? totalKgs;
  final String? sampleType;
  final SampleStatus status;
  final String? statusRaw;
  final String? remarks;
  /// Batch reference, e.g. `BATCH20260904001-01` (the API sends text, not an id).
  final String? batchRef;

  /// Billing company code the sample is for (e.g. `GOLAGHAT JALLAN`), or `all`.
  final String? forCompany;

  /// Buyer an outgoing sample goes to.
  final int? partyId;
  final String? partyName;
  final bool isParked;

  /// `completed` once tasted.
  final String? evaluationStatus;
  final DateTime? evaluatedAt;
  final String? evaluatedBy;
  final String? comments;
  final double? overallScore;

  /// Tasting scores by API field (see [scoreFields]); only those set.
  final Map<String, double> scores;

  bool get isTasted => evaluationStatus == 'completed' || overallScore != null;

  String get title => [gardenName ?? 'Garden #${gardenId ?? '–'}', ?grade].join(' · ');
  String get statusLabel => status == SampleStatus.unknown ? (statusRaw ?? 'Unknown') : status.label;

  factory Sample.fromJson(Map<String, dynamic> j) => Sample(
        raw: j,
        id: J.intOr(j['id'], 0),
        arrivalDate: J.date(j['arrival_date']),
        gardenId: J.integer(j['garden_id']),
        gardenName: J.nested(j, 'garden_name', 'garden', 'garden_name'),
        grade: J.code(j['grade']),
        invoicePrefix: J.code(j['invoice_prefix']),
        invoiceNo: J.str(j['inv_no']) ?? J.str(j['invoice_no']),
        packages: J.integer(j['pkgs'] ?? j['packages']),
        weight: J.dbl(j['nett'] ?? j['weight_per_sample'] ?? j['weight']),
        totalKgs: J.dbl(j['total_kgs']),
        sampleType: J.str(j['sample_type']),
        status: SampleStatus.parse(j['status']),
        statusRaw: J.str(j['status']),
        remarks: J.str(j['remarks']),
        batchRef: J.str(j['batch_id']),
        forCompany: J.str(j['for_company']),
        partyId: J.integer(j['party_id']) ?? J.integer(J.map(j['party'])?['id']),
        partyName: J.str(J.map(j['party'])?['buyer_name']) ?? J.str(J.map(j['party'])?['name']),
        isParked: J.boolOr(j['is_parked'], false),
        evaluationStatus: J.str(j['evaluation_status']),
        evaluatedAt: J.date(j['evaluated_at']),
        evaluatedBy: J.str(J.map(j['evaluated_by'])?['name']) ?? (j['evaluated_by'] is String ? J.str(j['evaluated_by']) : null),
        comments: J.str(j['evaluation_comments']),
        overallScore: J.dbl(j['overall_score']),
        scores: {
          for (final k in scoreFields.keys)
            if (J.dbl(j[k]) != null) k: J.dbl(j[k])!,
        },
      );
}
