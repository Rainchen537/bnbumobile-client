import 'me_life_presentation.dart';

const landmarkReviewConsentVersion = 'community.2026-09-14';

class CommunityPolicy {
  const CommunityPolicy({
    this.level = 3,
    this.readComments = false,
    this.readRatings = false,
    this.writeComments = false,
    this.writeRatings = false,
    this.react = false,
    this.revision = 0,
  });
  factory CommunityPolicy.fromJson(Map<String, dynamic> j) => CommunityPolicy(
    level: j['level'] as int,
    readComments: j['read_comments'] == true,
    readRatings: j['read_ratings'] == true,
    writeComments: j['write_comments'] == true,
    writeRatings: j['write_ratings'] == true,
    react: j['react'] == true,
    revision: j['revision'] as int,
  );
  final int level, revision;
  final bool readComments, readRatings, writeComments, writeRatings, react;
}

class LandmarkReview {
  LandmarkReview.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      source = (j['source'] ?? 'internal') as String,
      readOnly = j['read_only'] == true || j['source'] == '25doer',
      ratingScore = (j['rating_score'] as num?)?.toDouble(),
      images = List<String>.unmodifiable(
        (j['images'] as List? ?? []).cast<String>().where(
          (v) => RegExp(
            r'^/v2/public/landmarks/[a-z0-9-]+/review-images/[a-f0-9]{64}$',
          ).hasMatch(v),
        ),
      ),
      merchantReply = j['merchant_reply'] as String?,
      comment = (j['body'] ?? j['comment'] ?? '') as String,
      rating = (j['stars'] ?? j['overall_rating']) as int?,
      name = (j['author']?['name'] ?? '匿名同学') as String,
      seed = (j['author']?['seed'] ?? j['id']) as String,
      avatarUrl = j['author']?['avatar_url'] as String?,
      anonymous = j['author']?['anonymous'] != false,
      rootId = j['root_id'] as String?,
      replyTo = j['reply_to'] as String?,
      helpful = (j['helpful'] ?? 0) as int,
      replies = (j['reply_count'] ?? 0) as int,
      featured = j['featured'] == true,
      deleted = j['deleted'] == true,
      status = (j['status'] ?? j['moderation_status'] ?? 'visible') as String,
      hiddenReason = (j['reason'] ?? j['hidden_reason'] ?? '') as String,
      editedAt = DateTime.tryParse(j['edited_at'] as String? ?? ''),
      tags = List.unmodifiable(
        (j['tags'] as List? ?? []).map(
          (e) => LifeCommentTag.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      ),
      replyPreview = j['reply_preview'] is Map
          ? LandmarkReview.fromJson(
              Map<String, dynamic>.from(j['reply_preview'] as Map),
            )
          : null,
      version = j['version'] as int,
      updatedAt = DateTime.parse(j['updated_at'] as String),
      createdAt = DateTime.parse(
        (j['created_at'] ?? j['updated_at']) as String,
      );
  final String id, comment, name, seed, status, hiddenReason, source;
  final bool readOnly;
  final double? ratingScore;
  final List<String> images;
  final String? merchantReply;
  final String? avatarUrl, rootId, replyTo;
  final int? rating;
  final int helpful, replies, version;
  final bool anonymous, featured, deleted;
  bool get hidden => status == 'hidden';
  final DateTime updatedAt, createdAt;
  final DateTime? editedAt;
  final List<LifeCommentTag> tags;
  final LandmarkReview? replyPreview;
}

class LandmarkReviewPage {
  LandmarkReviewPage.withPolicy(LandmarkReviewPage page, this.policy)
    : items = page.items,
      total = page.total,
      average = page.average,
      ratingCount = page.ratingCount,
      counts = page.counts,
      ratingSummary = page.ratingSummary;

  LandmarkReviewPage.fromJson(Map<String, dynamic> j)
    : items = List.unmodifiable(
        (j['items'] as List).map(
          (i) => LandmarkReview.fromJson(Map<String, dynamic>.from(i as Map)),
        ),
      ),
      total = j['total'] as int,
      average =
          ((j.containsKey('rating_summary')
                      ? j['rating_summary']['score']
                      : j['summary']['average'])
                  as num?)
              ?.toDouble(),
      ratingSummary = Map<String, dynamic>.unmodifiable(
        j['rating_summary'] as Map? ?? {},
      ),
      ratingCount = (j['summary']['count'] ?? 0) as int,
      counts = List<int>.from(
        j['summary']['counts'] as List? ?? [0, 0, 0, 0, 0],
      ),
      policy = CommunityPolicy.fromJson(
        Map<String, dynamic>.from(j['policy'] as Map),
      );
  final List<LandmarkReview> items;
  final int total, ratingCount;
  final double? average;
  final Map<String, dynamic> ratingSummary;
  final List<int> counts;
  final CommunityPolicy policy;
}

class LandmarkReviewMine {
  const LandmarkReviewMine({
    this.review,
    this.suspendedUntil,
    this.canReview = true,
    this.stars,
    this.ratingVersion = 0,
    this.nextEditAt,
    this.profileName = '',
    this.anonymousName = '',
    this.seed = '',
    this.profileVersion = 0,
    this.helpfulIds = const {},
    this.ownedCommentIds = const {},
    this.policy = const CommunityPolicy(),
  });
  factory LandmarkReviewMine.fromJson(Map<String, dynamic> j) =>
      LandmarkReviewMine(
        review: j['comment'] == null
            ? null
            : LandmarkReview.fromJson(
                Map<String, dynamic>.from(j['comment'] as Map),
              ),
        canReview: j['can_review'] == true,
        stars: j['rating']?['stars'] as int?,
        ratingVersion: (j['rating']?['version'] ?? 0) as int,
        nextEditAt: DateTime.tryParse(
          j['rating']?['next_edit_at'] as String? ?? '',
        ),
        profileName: (j['profile']?['name'] ?? '') as String,
        anonymousName: (j['profile']?['anonymous_name'] ?? '') as String,
        seed: (j['profile']?['seed'] ?? '') as String,
        profileVersion: (j['profile']?['version'] ?? 0) as int,
        helpfulIds: Set<String>.from(j['helpful_ids'] as List? ?? []),
        ownedCommentIds: Set<String>.from(
          j['owned_comment_ids'] as List? ?? [],
        ),
        policy: CommunityPolicy.fromJson(
          Map<String, dynamic>.from(j['policy'] as Map),
        ),
      );
  final LandmarkReview? review;
  final DateTime? suspendedUntil, nextEditAt;
  final bool canReview;
  final int? stars;
  final int ratingVersion, profileVersion;
  final String profileName, anonymousName, seed;
  final Set<String> helpfulIds, ownedCommentIds;
  final CommunityPolicy policy;
}
