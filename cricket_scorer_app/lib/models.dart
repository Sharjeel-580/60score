// Data models for CricScore Offline. Pure Dart (no Flutter imports) so the
// scoring logic can be unit-tested easily. All classes are JSON-serializable
// for SharedPreferences persistence.
import 'dart:math' as math;

class Player {
  String id;
  String name;
  int jerseyNo;
  String role; // Batter / Bowler / All-Rounder / Wicket-Keeper
  String battingStyle; // Right-hand / Left-hand
  String bowlingStyle; // e.g. Right-arm fast, Left-arm spin, None
  bool isCaptain;
  bool isViceCaptain;
  bool isKeeper;
  String photoBase64; // optional player photo (base64 JPEG), '' if none

  Player({
    required this.id,
    required this.name,
    this.jerseyNo = 0,
    this.role = 'Batter',
    this.battingStyle = 'Right-hand',
    this.bowlingStyle = 'None',
    this.isCaptain = false,
    this.isViceCaptain = false,
    this.isKeeper = false,
    this.photoBase64 = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'jerseyNo': jerseyNo,
    'role': role,
    'battingStyle': battingStyle,
    'bowlingStyle': bowlingStyle,
    'isCaptain': isCaptain,
    'isViceCaptain': isViceCaptain,
    'isKeeper': isKeeper,
    'photoBase64': photoBase64,
  };

  factory Player.fromJson(Map<String, dynamic> j) => Player(
    id: j['id'] as String,
    name: j['name'] as String,
    jerseyNo: (j['jerseyNo'] as num?)?.toInt() ?? 0,
    role: j['role'] as String? ?? 'Batter',
    battingStyle: j['battingStyle'] as String? ?? 'Right-hand',
    bowlingStyle: j['bowlingStyle'] as String? ?? 'None',
    isCaptain: j['isCaptain'] as bool? ?? false,
    isViceCaptain: j['isViceCaptain'] as bool? ?? false,
    isKeeper: j['isKeeper'] as bool? ?? false,
    photoBase64: j['photoBase64'] as String? ?? '',
  );
}

class Team {
  String id;
  String name;
  List<Player> players;

  Team({required this.id, required this.name, List<Player>? players})
    : players = players ?? [];

  Player? playerById(String pid) {
    for (final p in players) {
      if (p.id == pid) return p;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'players': players.map((p) => p.toJson()).toList(),
  };

  factory Team.fromJson(Map<String, dynamic> j) => Team(
    id: j['id'] as String,
    name: j['name'] as String,
    players: ((j['players'] as List?) ?? [])
        .map((e) => Player.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class Tournament {
  String id;
  String name;
  List<String> teamIds;
  String venue;
  String logoBase64; // optional tournament logo (base64 JPEG), '' if none
  Map<String, int> pointsAdjustments; // teamId -> extra (custom) points
  /// Final (locked) playoff qualification: ordered team IDs, rank 1..4.
  /// Empty until the league stage is finalized. Derived by the playoff
  /// engine — never edited by hand.
  List<String> qualifiedTeamIds;
  /// True once league standings are final and seeds are locked.
  bool qualificationFinalized;
  /// True while this tournament is published to the public
  /// `published_tournaments` collection (search / follow, view-only).
  /// Publishing is always a manual owner action — never automatic.
  bool published;

  /// Overs per innings for this tournament's matches (v1.3.7).
  /// The match setup defaults a tournament fixture to this value, so
  /// a league's format (Super Sixty = 8) is set once, on the
  /// tournament, instead of per fixture. Records written before
  /// v1.3.7 have no such field and read as the Super Sixty default.
  int oversLimit;

  Tournament({
    required this.id,
    required this.name,
    List<String>? teamIds,
    this.venue = '',
    this.logoBase64 = '',
    Map<String, int>? pointsAdjustments,
    List<String>? qualifiedTeamIds,
    this.qualificationFinalized = false,
    this.published = false,
    this.oversLimit = 8,
  }) : teamIds = teamIds ?? [],
       pointsAdjustments = pointsAdjustments ?? {},
       qualifiedTeamIds = qualifiedTeamIds ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'teamIds': teamIds,
    'venue': venue,
    'logoBase64': logoBase64,
    'pointsAdjustments': pointsAdjustments,
    'qualifiedTeamIds': qualifiedTeamIds,
    'qualificationFinalized': qualificationFinalized,
    'published': published,
    'oversLimit': oversLimit,
  };

  factory Tournament.fromJson(Map<String, dynamic> j) {
    final adj = <String, int>{};
    ((j['pointsAdjustments'] as Map?) ?? {}).forEach((k, v) {
      adj[k as String] = (v as num).toInt();
    });
    return Tournament(
      id: j['id'] as String,
      name: j['name'] as String,
      teamIds: ((j['teamIds'] as List?) ?? []).map((e) => e as String).toList(),
      venue: j['venue'] as String? ?? '',
      logoBase64: j['logoBase64'] as String? ?? '',
      pointsAdjustments: adj,
      qualifiedTeamIds:
          ((j['qualifiedTeamIds'] as List?) ?? [])
              .map((e) => e as String)
              .toList(),
      qualificationFinalized: j['qualificationFinalized'] as bool? ?? false,
      published: j['published'] as bool? ?? false,
      oversLimit: (j['oversLimit'] as num?)?.toInt() ?? 8,
    );
  }
}

/// One delivered ball.
class BallEvent {
  int inningsNo;
  String strikerId;
  String nonStrikerId;
  String bowlerId;
  String extraType; // none / wide / noBall / bye / legBye
  int
  batRuns; // runs credited to bat (or run for bye/leg-bye/wide extras below)
  int extraRuns; // additional runs beyond the wide penalty (wide only)
  bool isWicket;
  String wicketType; // '' or bowled/caught/lbw/runOut/stumped/hitWicket
  String outPlayerId; // '' if none
  String fielderId; // '' if none (catch / run-out / stumping credit)
  int? zone; // legacy wagon-wheel zone 1..8 (read-only, replaced by shotX/shotY)
  double? shotX; // wagon-wheel shot point, normalized -1..1 (boundary = 1.0)
  double? shotY; // wagon-wheel shot point, normalized -1..1 (boundary = 1.0)
  int totalRuns; // total team runs from this delivery
  bool legalBall;

  BallEvent({
    this.inningsNo = 1,
    required this.strikerId,
    required this.nonStrikerId,
    required this.bowlerId,
    this.extraType = 'none',
    this.batRuns = 0,
    this.extraRuns = 0,
    this.isWicket = false,
    this.wicketType = '',
    this.outPlayerId = '',
    this.fielderId = '',
    this.zone,
    this.shotX,
    this.shotY,
    this.totalRuns = 0,
    this.legalBall = true,
  });

  Map<String, dynamic> toJson() => {
    'inningsNo': inningsNo,
    'strikerId': strikerId,
    'nonStrikerId': nonStrikerId,
    'bowlerId': bowlerId,
    'extraType': extraType,
    'batRuns': batRuns,
    'extraRuns': extraRuns,
    'isWicket': isWicket,
    'wicketType': wicketType,
    'outPlayerId': outPlayerId,
    'fielderId': fielderId,
    'zone': zone,
    'shotX': shotX,
    'shotY': shotY,
    'totalRuns': totalRuns,
    'legalBall': legalBall,
  };

  factory BallEvent.fromJson(Map<String, dynamic> j) => BallEvent(
    inningsNo: (j['inningsNo'] as num?)?.toInt() ?? 1,
    strikerId: j['strikerId'] as String,
    nonStrikerId: j['nonStrikerId'] as String,
    bowlerId: j['bowlerId'] as String,
    extraType: j['extraType'] as String? ?? 'none',
    batRuns: (j['batRuns'] as num?)?.toInt() ?? 0,
    extraRuns: (j['extraRuns'] as num?)?.toInt() ?? 0,
    isWicket: j['isWicket'] as bool? ?? false,
    wicketType: j['wicketType'] as String? ?? '',
    outPlayerId: j['outPlayerId'] as String? ?? '',
    fielderId: j['fielderId'] as String? ?? '',
    zone: (j['zone'] as num?)?.toInt(),
    shotX: (j['shotX'] as num?)?.toDouble() ??
        _legacyZonePoint((j['zone'] as num?)?.toInt()).$1,
    shotY: (j['shotY'] as num?)?.toDouble() ??
        _legacyZonePoint((j['zone'] as num?)?.toInt()).$2,
    totalRuns: (j['totalRuns'] as num?)?.toInt() ?? 0,
    legalBall: j['legalBall'] as bool? ?? true,
  );

  /// Short display, e.g. "4", "W", "1wd", "1nb", "2b".
  String get display {
    if (isWicket && batRuns == 0 && extraType == 'none') return 'W';
    switch (extraType) {
      case 'wide':
        return '${1 + extraRuns}wd';
      case 'noBall':
        return batRuns == 0 ? 'nb' : '$batRuns+nb';
      case 'bye':
        return '${batRuns}b';
      case 'legBye':
        return '${batRuns}lb';
      default:
        return isWicket ? (batRuns > 0 ? '$batRuns+W' : 'W') : '$batRuns';
    }
  }
}

/// Converts a legacy wagon-wheel zone (1..8) to a normalized shot point.
/// Returns (null, null) when the zone is null.
(double?, double?) _legacyZonePoint(int? zone) {
  if (zone == null || zone < 1 || zone > 8) return (null, null);
  final mid = (zone - 1) * math.pi / 4 + math.pi / 4;
  return (0.72 * math.cos(mid), 0.72 * math.sin(mid));
}

class BatFig {
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  bool out = false;
  bool batted = false;
  String howOut = '';

  BatFig();

  Map<String, dynamic> toJson() => {
    'runs': runs,
    'balls': balls,
    'fours': fours,
    'sixes': sixes,
    'out': out,
    'batted': batted,
    'howOut': howOut,
  };

  factory BatFig.fromJson(Map<String, dynamic> j) {
    final f = BatFig();
    f.runs = (j['runs'] as num?)?.toInt() ?? 0;
    f.balls = (j['balls'] as num?)?.toInt() ?? 0;
    f.fours = (j['fours'] as num?)?.toInt() ?? 0;
    f.sixes = (j['sixes'] as num?)?.toInt() ?? 0;
    f.out = j['out'] as bool? ?? false;
    f.batted = j['batted'] as bool? ?? false;
    f.howOut = j['howOut'] as String? ?? '';
    return f;
  }
}

class BowlFig {
  int legalBalls = 0;
  int runs = 0; // runs conceded (bat + wides + no-ball penalties; not byes)
  int wickets = 0;
  int maidens = 0;
  int wides = 0;
  int noBalls = 0;

  BowlFig();

  Map<String, dynamic> toJson() => {
    'legalBalls': legalBalls,
    'runs': runs,
    'wickets': wickets,
    'maidens': maidens,
    'wides': wides,
    'noBalls': noBalls,
  };

  factory BowlFig.fromJson(Map<String, dynamic> j) {
    final f = BowlFig();
    f.legalBalls = (j['legalBalls'] as num?)?.toInt() ?? 0;
    f.runs = (j['runs'] as num?)?.toInt() ?? 0;
    f.wickets = (j['wickets'] as num?)?.toInt() ?? 0;
    f.maidens = (j['maidens'] as num?)?.toInt() ?? 0;
    f.wides = (j['wides'] as num?)?.toInt() ?? 0;
    f.noBalls = (j['noBalls'] as num?)?.toInt() ?? 0;
    return f;
  }
}

class FallOfWicket {
  int wicketNo;
  int runs;
  String overText;
  String playerId;

  FallOfWicket(this.wicketNo, this.runs, this.overText, this.playerId);

  Map<String, dynamic> toJson() => {
    'wicketNo': wicketNo,
    'runs': runs,
    'overText': overText,
    'playerId': playerId,
  };

  factory FallOfWicket.fromJson(Map<String, dynamic> j) => FallOfWicket(
    (j['wicketNo'] as num).toInt(),
    (j['runs'] as num).toInt(),
    j['overText'] as String,
    j['playerId'] as String,
  );
}

class InningsState {
  String battingTeamId;
  String bowlingTeamId;
  List<String> battingXI;
  List<String> bowlingXI;
  int oversLimit;
  int ballsPerOver;
  int totalRuns = 0;
  int wickets = 0;
  int legalBalls = 0;
  String strikerId = '';
  String nonStrikerId = '';
  String currentBowlerId = '';
  String lastBowlerId = '';
  bool awaitingBatter = false;
  bool awaitingBowler = false;
  Map<String, BatFig> batting = {};
  Map<String, BowlFig> bowling = {};
  int widesRuns = 0;
  int noBallRuns = 0; // penalty runs only (count of no-balls * 1)
  int byeRuns = 0;
  int legByeRuns = 0;
  int noBallCount = 0;
  int wideCount = 0;
  List<BallEvent> events = [];
  List<FallOfWicket> fallOfWickets = [];
  List<String> undoStack =
      []; // JSON snapshots of this innings before each ball
  int currentOverBowlerRuns = 0; // for maiden detection
  int currentOverTeamRuns = 0; // all team runs this over (maiden detection)
  int target = 0; // 0 = no target (first innings)
  int maxWickets = 0; // 0 = default (XI - 1); set from match settings
  bool widePenalty = true;
  bool noBallPenalty = true;

  int get effectiveMaxWickets =>
      maxWickets > 0 ? maxWickets : battingXI.length - 1;

  bool get isComplete =>
      legalBalls >= oversLimit * ballsPerOver ||
      wickets >= effectiveMaxWickets ||
      (target > 0 && totalRuns >= target);

  int get extrasTotal => widesRuns + noBallRuns + byeRuns + legByeRuns;

  InningsState({
    required this.battingTeamId,
    required this.bowlingTeamId,
    required this.battingXI,
    required this.bowlingXI,
    required this.oversLimit,
    this.ballsPerOver = 6,
  });

  Map<String, dynamic> toJson() => {
    'battingTeamId': battingTeamId,
    'bowlingTeamId': bowlingTeamId,
    'battingXI': battingXI,
    'bowlingXI': bowlingXI,
    'oversLimit': oversLimit,
    'ballsPerOver': ballsPerOver,
    'totalRuns': totalRuns,
    'wickets': wickets,
    'legalBalls': legalBalls,
    'strikerId': strikerId,
    'nonStrikerId': nonStrikerId,
    'currentBowlerId': currentBowlerId,
    'lastBowlerId': lastBowlerId,
    'awaitingBatter': awaitingBatter,
    'awaitingBowler': awaitingBowler,
    'batting': batting.map((k, v) => MapEntry(k, v.toJson())),
    'bowling': bowling.map((k, v) => MapEntry(k, v.toJson())),
    'widesRuns': widesRuns,
    'noBallRuns': noBallRuns,
    'byeRuns': byeRuns,
    'legByeRuns': legByeRuns,
    'noBallCount': noBallCount,
    'wideCount': wideCount,
    'events': events.map((e) => e.toJson()).toList(),
    'fallOfWickets': fallOfWickets.map((f) => f.toJson()).toList(),
    'undoStack': undoStack,
    'currentOverBowlerRuns': currentOverBowlerRuns,
    'currentOverTeamRuns': currentOverTeamRuns,
    'maxWickets': maxWickets,
    'widePenalty': widePenalty,
    'noBallPenalty': noBallPenalty,
    'target': target,
  };

  factory InningsState.fromJson(Map<String, dynamic> j) {
    final s = InningsState(
      battingTeamId: j['battingTeamId'] as String,
      bowlingTeamId: j['bowlingTeamId'] as String,
      battingXI: ((j['battingXI'] as List?) ?? [])
          .map((e) => e as String)
          .toList(),
      bowlingXI: ((j['bowlingXI'] as List?) ?? [])
          .map((e) => e as String)
          .toList(),
      oversLimit: (j['oversLimit'] as num?)?.toInt() ?? 20,
      ballsPerOver: (j['ballsPerOver'] as num?)?.toInt() ?? 6,
    );
    s.totalRuns = (j['totalRuns'] as num?)?.toInt() ?? 0;
    s.wickets = (j['wickets'] as num?)?.toInt() ?? 0;
    s.legalBalls = (j['legalBalls'] as num?)?.toInt() ?? 0;
    s.strikerId = j['strikerId'] as String? ?? '';
    s.nonStrikerId = j['nonStrikerId'] as String? ?? '';
    s.currentBowlerId = j['currentBowlerId'] as String? ?? '';
    s.lastBowlerId = j['lastBowlerId'] as String? ?? '';
    s.awaitingBatter = j['awaitingBatter'] as bool? ?? false;
    s.awaitingBowler = j['awaitingBowler'] as bool? ?? false;
    final bat = (j['batting'] as Map?) ?? {};
    bat.forEach(
      (k, v) =>
          s.batting[k as String] = BatFig.fromJson(v as Map<String, dynamic>),
    );
    final bowl = (j['bowling'] as Map?) ?? {};
    bowl.forEach(
      (k, v) =>
          s.bowling[k as String] = BowlFig.fromJson(v as Map<String, dynamic>),
    );
    s.widesRuns = (j['widesRuns'] as num?)?.toInt() ?? 0;
    s.noBallRuns = (j['noBallRuns'] as num?)?.toInt() ?? 0;
    s.byeRuns = (j['byeRuns'] as num?)?.toInt() ?? 0;
    s.legByeRuns = (j['legByeRuns'] as num?)?.toInt() ?? 0;
    s.noBallCount = (j['noBallCount'] as num?)?.toInt() ?? 0;
    s.wideCount = (j['wideCount'] as num?)?.toInt() ?? 0;
    s.events = ((j['events'] as List?) ?? [])
        .map((e) => BallEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    s.fallOfWickets = ((j['fallOfWickets'] as List?) ?? [])
        .map((e) => FallOfWicket.fromJson(e as Map<String, dynamic>))
        .toList();
    s.undoStack = ((j['undoStack'] as List?) ?? [])
        .map((e) => e as String)
        .toList();
    s.currentOverBowlerRuns =
        (j['currentOverBowlerRuns'] as num?)?.toInt() ?? 0;
    s.currentOverTeamRuns = (j['currentOverTeamRuns'] as num?)?.toInt() ?? 0;
    s.maxWickets = (j['maxWickets'] as num?)?.toInt() ?? 0;
    s.widePenalty = j['widePenalty'] as bool? ?? true;
    s.noBallPenalty = j['noBallPenalty'] as bool? ?? true;
    s.target = (j['target'] as num?)?.toInt() ?? 0;
    return s;
  }
}

class Match {
  String id;
  String? tournamentId;
  String teamAId;
  String teamBId;
  List<String> xiA;
  List<String> xiB;
  int oversLimit;
  int ballsPerOver;
  String venue;
  String dateIso;
  String tossWinnerId;
  String tossDecision; // bat / bowl (for toss winner)
  /// Fixture/match lifecycle: upcoming (scheduled fixture) / live /
  /// completed / noResult / cancelled.
  String status; // upcoming / live / completed / noResult / cancelled
  /// Tournament stage: league / semifinal1 / semifinal2 / final.
  /// League fixtures and playoff fixtures share this model; the stage
  /// tells the playoff engine which matches it owns.
  String stage;
  List<InningsState> innings;
  String resultText;
  int totalWickets; // 0 = default XI-1
  bool lastManStands;
  bool widePenalty;
  bool noBallPenalty;
  String manOfMatchId;
  String matchTitle; // e.g. "Final" (optional)
  String ballType; // Tennis Ball / Leather Ball / Other
  String season; // e.g. "2025" (optional)

  Match({
    required this.id,
    this.tournamentId,
    required this.teamAId,
    required this.teamBId,
    required this.xiA,
    required this.xiB,
    this.oversLimit = 20,
    this.ballsPerOver = 6,
    this.venue = '',
    this.dateIso = '',
    required this.tossWinnerId,
    this.tossDecision = 'bat',
    this.status = 'live',
    this.stage = 'league',
    List<InningsState>? innings,
    this.resultText = '',
    this.totalWickets = 0,
    this.lastManStands = false,
    this.widePenalty = true,
    this.noBallPenalty = true,
    this.manOfMatchId = '',
    this.matchTitle = '',
    this.ballType = 'Tennis Ball',
    this.season = '',
  }) : innings = innings ?? [];

  String get battingFirstId {
    // team that bats first based on toss
    if (tossWinnerId == teamAId) {
      return tossDecision == 'bat' ? teamAId : teamBId;
    }
    return tossDecision == 'bat' ? teamBId : teamAId;
  }

  String get battingSecondId => battingFirstId == teamAId ? teamBId : teamAId;

  List<String> xiFor(String teamId) => teamId == teamAId ? xiA : xiB;

  Map<String, dynamic> toJson() => {
    'id': id,
    'tournamentId': tournamentId,
    'teamAId': teamAId,
    'teamBId': teamBId,
    'xiA': xiA,
    'xiB': xiB,
    'oversLimit': oversLimit,
    'ballsPerOver': ballsPerOver,
    'venue': venue,
    'dateIso': dateIso,
    'tossWinnerId': tossWinnerId,
    'tossDecision': tossDecision,
    'status': status,
    'stage': stage,
    'innings': innings.map((i) => i.toJson()).toList(),
    'resultText': resultText,
    'totalWickets': totalWickets,
    'lastManStands': lastManStands,
    'widePenalty': widePenalty,
    'noBallPenalty': noBallPenalty,
    'manOfMatchId': manOfMatchId,
    'matchTitle': matchTitle,
    'ballType': ballType,
    'season': season,
  };

  factory Match.fromJson(Map<String, dynamic> j) {
    final m = Match(
      id: j['id'] as String,
      tournamentId: j['tournamentId'] as String?,
      teamAId: j['teamAId'] as String,
      teamBId: j['teamBId'] as String,
      xiA: ((j['xiA'] as List?) ?? []).map((e) => e as String).toList(),
      xiB: ((j['xiB'] as List?) ?? []).map((e) => e as String).toList(),
      oversLimit: (j['oversLimit'] as num?)?.toInt() ?? 20,
      ballsPerOver: (j['ballsPerOver'] as num?)?.toInt() ?? 6,
      venue: j['venue'] as String? ?? '',
      dateIso: j['dateIso'] as String? ?? '',
      tossWinnerId: j['tossWinnerId'] as String,
      tossDecision: j['tossDecision'] as String? ?? 'bat',
      status: j['status'] as String? ?? 'live',
      stage: j['stage'] as String? ?? 'league',
      innings: ((j['innings'] as List?) ?? [])
          .map((e) => InningsState.fromJson(e as Map<String, dynamic>))
          .toList(),
      resultText: j['resultText'] as String? ?? '',
      totalWickets: (j['totalWickets'] as num?)?.toInt() ?? 0,
      lastManStands: j['lastManStands'] as bool? ?? false,
      widePenalty: j['widePenalty'] as bool? ?? true,
      noBallPenalty: j['noBallPenalty'] as bool? ?? true,
      manOfMatchId: j['manOfMatchId'] as String? ?? '',
      matchTitle: j['matchTitle'] as String? ?? '',
      ballType: j['ballType'] as String? ?? 'Tennis Ball',
      season: j['season'] as String? ?? '',
    );
    // v1.3.4: standard matches saved by older builds can carry an
    // impossible 11-wicket innings (the old "11 wickets" setup
    // option). Clamp stored innings to XI − 1 wickets on load, so
    // all-out and the result margin use 10 wickets for a full XI
    // (2 down = "won by 8 wickets"). Last-man-stands matches are
    // exempt: there the last batter really can be dismissed, so
    // maxWickets == XI length is that format's design.
    if (!m.lastManStands) {
      for (final inn in m.innings) {
        // v1.3.7: the cap is also never above 10 — an over-long
        // stored XI (12 names) must not resurrect 11 wickets via
        // XI − 1; a side can lose at most 10 wickets.
        var cap = inn.battingXI.length - 1;
        if (cap > 10) cap = 10;
        if (cap >= 1 && inn.maxWickets > cap) inn.maxWickets = cap;
      }
    }
    return m;
  }
}

String oversText(int legalBalls, int ballsPerOver) {
  if (ballsPerOver <= 0) return '0.0';
  return '${legalBalls ~/ ballsPerOver}.${legalBalls % ballsPerOver}';
}

/// A player registered for the league (Registration section). The
/// registration list is the source of the draft pool. When a registered
/// player is drafted / added to a team squad, a [Player] with the SAME id
/// is created so career stats unify across modules.
class RegPlayer {
  String id;
  String name;
  String role;
  String availability; // Available / Not Available
  String area;
  String phone;
  String remarks;
  String battingStyle;
  String bowlingStyle;
  int age;
  String category;
  String regStatus; // Confirmed / Pending
  String teamName; // optional intended team (from import), '' if none
  int jerseyNo;
  bool isCaptain;
  bool isKeeper;
  String photoBase64; // optional player photo (base64 JPEG), '' if none

  RegPlayer({
    required this.id,
    required this.name,
    this.role = 'Batter',
    this.availability = 'Available',
    this.area = '',
    this.phone = '',
    this.remarks = '',
    this.battingStyle = 'Right-hand',
    this.bowlingStyle = 'None',
    this.age = 0,
    this.category = '',
    this.regStatus = 'Confirmed',
    this.teamName = '',
    this.jerseyNo = 0,
    this.isCaptain = false,
    this.isKeeper = false,
    this.photoBase64 = '',
  });

  Player toTeamPlayer() => Player(
    id: id,
    name: name,
    jerseyNo: jerseyNo,
    role: role,
    battingStyle: battingStyle,
    bowlingStyle: bowlingStyle,
    isCaptain: isCaptain,
    isKeeper: isKeeper,
    photoBase64: photoBase64,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'availability': availability,
    'area': area,
    'phone': phone,
    'remarks': remarks,
    'battingStyle': battingStyle,
    'bowlingStyle': bowlingStyle,
    'age': age,
    'category': category,
    'regStatus': regStatus,
    'teamName': teamName,
    'jerseyNo': jerseyNo,
    'isCaptain': isCaptain,
    'isKeeper': isKeeper,
    'photoBase64': photoBase64,
  };

  factory RegPlayer.fromJson(Map<String, dynamic> j) => RegPlayer(
    id: j['id'] as String,
    name: j['name'] as String,
    role: j['role'] as String? ?? 'Batter',
    availability: j['availability'] as String? ?? 'Available',
    area: j['area'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    remarks: j['remarks'] as String? ?? '',
    battingStyle: j['battingStyle'] as String? ?? 'Right-hand',
    bowlingStyle: j['bowlingStyle'] as String? ?? 'None',
    age: (j['age'] as num?)?.toInt() ?? 0,
    category: j['category'] as String? ?? '',
    regStatus: j['regStatus'] as String? ?? 'Confirmed',
    teamName: j['teamName'] as String? ?? '',
    jerseyNo: (j['jerseyNo'] as num?)?.toInt() ?? 0,
    isCaptain: j['isCaptain'] as bool? ?? false,
    isKeeper: j['isKeeper'] as bool? ?? false,
    photoBase64: j['photoBase64'] as String? ?? '',
  );
}

/// One manually-entered past performance ("Add past scores"). Adds into
/// career totals and is labelled manual.
class ManualStatEntry {
  String id;
  String playerId;
  String playerName;
  String matchLabel;
  String dateIso;
  int runs;
  int balls;
  int fours;
  int sixes;
  bool notOut;
  int wickets;
  int runsConceded;
  int ballsBowled;
  int catches;
  int stumpings;

  ManualStatEntry({
    required this.id,
    required this.playerId,
    required this.playerName,
    this.matchLabel = '',
    this.dateIso = '',
    this.runs = 0,
    this.balls = 0,
    this.fours = 0,
    this.sixes = 0,
    this.notOut = false,
    this.wickets = 0,
    this.runsConceded = 0,
    this.ballsBowled = 0,
    this.catches = 0,
    this.stumpings = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'playerId': playerId,
    'playerName': playerName,
    'matchLabel': matchLabel,
    'dateIso': dateIso,
    'runs': runs,
    'balls': balls,
    'fours': fours,
    'sixes': sixes,
    'notOut': notOut,
    'wickets': wickets,
    'runsConceded': runsConceded,
    'ballsBowled': ballsBowled,
    'catches': catches,
    'stumpings': stumpings,
  };

  factory ManualStatEntry.fromJson(Map<String, dynamic> j) => ManualStatEntry(
    id: j['id'] as String,
    playerId: j['playerId'] as String,
    playerName: j['playerName'] as String? ?? '',
    matchLabel: j['matchLabel'] as String? ?? '',
    dateIso: j['dateIso'] as String? ?? '',
    runs: (j['runs'] as num?)?.toInt() ?? 0,
    balls: (j['balls'] as num?)?.toInt() ?? 0,
    fours: (j['fours'] as num?)?.toInt() ?? 0,
    sixes: (j['sixes'] as num?)?.toInt() ?? 0,
    notOut: j['notOut'] as bool? ?? false,
    wickets: (j['wickets'] as num?)?.toInt() ?? 0,
    runsConceded: (j['runsConceded'] as num?)?.toInt() ?? 0,
    ballsBowled: (j['ballsBowled'] as num?)?.toInt() ?? 0,
    catches: (j['catches'] as num?)?.toInt() ?? 0,
    stumpings: (j['stumpings'] as num?)?.toInt() ?? 0,
  );
}

class DraftPick {
  int round;
  int pickNo; // overall pick number, 1-based
  String teamId;
  String playerId; // RegPlayer id
  String playerName;

  DraftPick({
    required this.round,
    required this.pickNo,
    required this.teamId,
    required this.playerId,
    required this.playerName,
  });

  Map<String, dynamic> toJson() => {
    'round': round,
    'pickNo': pickNo,
    'teamId': teamId,
    'playerId': playerId,
    'playerName': playerName,
  };

  factory DraftPick.fromJson(Map<String, dynamic> j) => DraftPick(
    round: (j['round'] as num).toInt(),
    pickNo: (j['pickNo'] as num).toInt(),
    teamId: j['teamId'] as String,
    playerId: j['playerId'] as String,
    playerName: j['playerName'] as String? ?? '',
  );
}

/// An offline manual-pick draft. Simple rounds, no categories.
/// Newer settings fields are optional with defaults so drafts saved by
/// older versions still load (fromJson uses `?? defaults`).
class Draft {
  String id;
  String name;
  List<String> teamIds; // pick order (linear repeating)
  int squadSize; // == number of rounds (one pick per team per round)
  bool snakeOrder;
  List<DraftPick> picks;
  String status; // active / completed
  bool appliedToTeams; // squads copied into Scorer teams
  // --- v1.1.2 drafting settings (all optional, backward compatible) ---
  String tournamentId;
  int pickTimeSeconds;
  bool allowManualSkip;
  bool allowUndo;
  bool autoNextPick; // default OFF: fully manual unless the user opts in
  bool showPlayerRoles;
  List<String> manualPickOrder; // custom pick order, [] = use teamIds order
  Map<String, List<String>> manualRoundPicks; // round ('1','2',..) -> teamIds
  int createdAt; // ms since epoch, 0 when unknown (old drafts)

  Draft({
    required this.id,
    required this.name,
    required this.teamIds,
    this.squadSize = 14,
    this.snakeOrder = false,
    List<DraftPick>? picks,
    this.status = 'active',
    this.appliedToTeams = false,
    this.tournamentId = '',
    this.pickTimeSeconds = 30,
    this.allowManualSkip = true,
    this.allowUndo = true,
    this.autoNextPick = false,
    this.showPlayerRoles = true,
    List<String>? manualPickOrder,
    Map<String, List<String>>? manualRoundPicks,
    this.createdAt = 0,
  }) : picks = picks ?? [],
       manualPickOrder = manualPickOrder ?? [],
       manualRoundPicks = manualRoundPicks ?? {};

  int get totalPicks => squadSize * teamIds.length;
  bool get isComplete => picks.length >= totalPicks;
  int get rounds => squadSize;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'teamIds': teamIds,
    'squadSize': squadSize,
    'snakeOrder': snakeOrder,
    'picks': picks.map((p) => p.toJson()).toList(),
    'status': status,
    'appliedToTeams': appliedToTeams,
    'tournamentId': tournamentId,
    'pickTimeSeconds': pickTimeSeconds,
    'allowManualSkip': allowManualSkip,
    'allowUndo': allowUndo,
    'autoNextPick': autoNextPick,
    'showPlayerRoles': showPlayerRoles,
    'manualPickOrder': manualPickOrder,
    'manualRoundPicks': manualRoundPicks,
    'createdAt': createdAt,
  };

  factory Draft.fromJson(Map<String, dynamic> j) {
    final mrp = <String, List<String>>{};
    ((j['manualRoundPicks'] as Map?) ?? {}).forEach((k, v) {
      mrp[k as String] = ((v as List?) ?? []).map((e) => e as String).toList();
    });
    return Draft(
      id: j['id'] as String,
      name: j['name'] as String,
      teamIds: ((j['teamIds'] as List?) ?? []).map((e) => e as String).toList(),
      squadSize: (j['squadSize'] as num?)?.toInt() ?? 14,
      snakeOrder: j['snakeOrder'] as bool? ?? false,
      picks: ((j['picks'] as List?) ?? [])
          .map((e) => DraftPick.fromJson(e as Map<String, dynamic>))
          .toList(),
      status: j['status'] as String? ?? 'active',
      appliedToTeams: j['appliedToTeams'] as bool? ?? false,
      tournamentId: j['tournamentId'] as String? ?? '',
      pickTimeSeconds: (j['pickTimeSeconds'] as num?)?.toInt() ?? 30,
      allowManualSkip: j['allowManualSkip'] as bool? ?? true,
      allowUndo: j['allowUndo'] as bool? ?? true,
      autoNextPick: j['autoNextPick'] as bool? ?? false,
      showPlayerRoles: j['showPlayerRoles'] as bool? ?? true,
      manualPickOrder:
          ((j['manualPickOrder'] as List?) ?? [])
              .map((e) => e as String)
              .toList(),
      manualRoundPicks: mrp,
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}
