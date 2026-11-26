import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'main.dart';

enum SkillProficiency {
  none(
    0.0,
    'None',
    'No experience',
    Icons.radio_button_unchecked,
    Color(0xff94a3b8),
  ),
  basic(
    0.33,
    'Basic',
    'Foundational / Theory',
    Icons.school_outlined,
    Color(0xff3b82f6),
  ),
  intermediate(
    0.66,
    'Hands-on',
    'Built real projects',
    Icons.build_circle_outlined,
    Color(0xff8b5cf6),
  ),
  advanced(
    1.0,
    'Proficient',
    'Production-ready',
    Icons.verified_outlined,
    Color(0xff10b981),
  );

  const SkillProficiency(
    this.value,
    this.label,
    this.description,
    this.icon,
    this.color,
  );
  final double value;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

class SkillGapItem {
  SkillGapItem({
    required this.id,
    required this.name,
    required this.type,
    required this.requiredLevel,
    required this.userProficiency,
  });

  final String id;
  final String name;
  final String type; // 'core' or 'secondary'
  final String requiredLevel; // 'beginner', 'intermediate', 'advanced'
  SkillProficiency userProficiency;

  double get targetValue {
    switch (requiredLevel.toLowerCase()) {
      case 'beginner':
        return 0.35;
      case 'intermediate':
        return 0.70;
      case 'advanced':
      default:
        return 0.95;
    }
  }

  bool get isMastered => userProficiency.value >= targetValue;
  bool get isCriticalGap =>
      type == 'core' && userProficiency.value < targetValue;
  bool get isSecondaryGap =>
      type != 'core' && userProficiency.value < targetValue;
}

class SkillGapReport {
  SkillGapReport({
    required this.career,
    required this.roadmap,
    required this.items,
    required this.currentStatus,
    required this.yearsExperience,
    required this.weeklyHours,
    required this.additionalNotes,
  });

  final Map<String, dynamic> career;
  final Map<String, dynamic> roadmap;
  final List<SkillGapItem> items;
  final String currentStatus;
  final String yearsExperience;
  final int weeklyHours;
  final String additionalNotes;

  List<SkillGapItem> get masteredSkills =>
      items.where((i) => i.isMastered).toList();
  List<SkillGapItem> get criticalGaps =>
      items.where((i) => i.isCriticalGap).toList();
  List<SkillGapItem> get secondaryGaps =>
      items.where((i) => i.isSecondaryGap).toList();

  int get readinessScore {
    if (items.isEmpty) return 0;
    double totalWeight = 0;
    double earnedWeight = 0;
    for (final item in items) {
      final weight = item.type == 'core' ? 1.6 : 1.0;
      totalWeight += weight;
      final ratio = (item.userProficiency.value / item.targetValue).clamp(
        0.0,
        1.0,
      );
      earnedWeight += weight * ratio;
    }
    double score = (earnedWeight / totalWeight) * 100;
    if (yearsExperience == '1-3 years') score += 3;
    if (yearsExperience == '3+ years') score += 6;
    return score.round().clamp(0, 100);
  }

  String get readinessTier {
    final score = readinessScore;
    if (score >= 82) return 'Fast-Track / Role-Ready';
    if (score >= 60) return 'Strong Core / Bridgeable Gaps';
    if (score >= 35) return 'Foundations Needed';
    return 'Ground-Up Learner';
  }

  Color get tierColor {
    final score = readinessScore;
    if (score >= 82) return const Color(0xff059669);
    if (score >= 60) return const Color(0xff0284c7);
    if (score >= 35) return const Color(0xffd97706);
    return const Color(0xffe11d48);
  }

  String get recalibratedTimeline {
    final timeToEntry = career['timeToEntry'] as Map<String, dynamic>? ?? {};
    final minMonths = (timeToEntry['minMonths'] as num?)?.toDouble() ?? 6.0;
    final maxMonths = (timeToEntry['maxMonths'] as num?)?.toDouble() ?? 12.0;

    final remainingRatio = (100 - readinessScore) / 100.0;
    // Standard baseline assumes ~12 hrs/week.
    final hoursMultiplier = (12.0 / weeklyHours.clamp(5, 40)).clamp(0.5, 2.0);

    final rawMinWeeks = (minMonths * 4.3 * remainingRatio * hoursMultiplier)
        .round()
        .clamp(2, 60);
    final rawMaxWeeks = (maxMonths * 4.3 * remainingRatio * hoursMultiplier)
        .round()
        .clamp(rawMinWeeks, 80);

    if (rawMaxWeeks <= 4) {
      return '$rawMinWeeks–$rawMaxWeeks weeks (Immediate prep)';
    } else if (rawMaxWeeks <= 16) {
      return '$rawMinWeeks–$rawMaxWeeks weeks (~${(rawMaxWeeks / 4.3).toStringAsFixed(1)} months)';
    } else {
      final mMin = (rawMinWeeks / 4.3).round();
      final mMax = (rawMaxWeeks / 4.3).round();
      return '$mMin–$mMax months (vs. ${minMonths.round()}–${maxMonths.round()} months standard)';
    }
  }

  List<String> get skippableStages {
    final stages = (roadmap['stages'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    if (stages.isEmpty) return [];
    final skippable = <String>[];

    // If readiness is high or foundations are covered
    if (readinessScore >= 50 && stages.isNotEmpty) {
      skippable.add(stages.first['name'] as String? ?? 'Foundations');
    }
    if (readinessScore >= 75 && stages.length > 2) {
      skippable.add(stages[1]['name'] as String? ?? 'Core Concepts');
    }
    return skippable;
  }

  Map<String, dynamic>? get recommendedStartingStage {
    final stages = (roadmap['stages'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    if (stages.isEmpty) return null;
    if (readinessScore >= 75 && stages.length >= 3) {
      return stages[2]; // Jump to Advanced / Applied Projects
    }
    if (readinessScore >= 50 && stages.length >= 2) {
      return stages[1]; // Jump to Core Concepts
    }
    return stages.first;
  }
}

class SkillGapPage extends ConsumerStatefulWidget {
  const SkillGapPage({super.key, this.initialCareerId});
  final String? initialCareerId;

  @override
  ConsumerState<SkillGapPage> createState() => _SkillGapPageState();
}

class _SkillGapPageState extends ConsumerState<SkillGapPage> {
  int _currentStep = 0; // 0: Setup, 1: Rating Matrix, 2: Report & Agent
  String? _selectedCareerId;
  String _currentStatus = 'Career Switcher (Learning tech)';
  String _yearsExperience = '< 1 year';
  int _weeklyHours = 15;
  final TextEditingController _notesController = TextEditingController();

  final Map<String, SkillProficiency> _userRatings = {};
  SkillGapReport? _generatedReport;

  // AI Agent Chat state
  final List<({bool fromUser, String text})> _agentMessages = [];
  final TextEditingController _agentInputController = TextEditingController();
  bool _agentSending = false;

  final List<String> _statusOptions = [
    'Student / Recent Graduate',
    'Self-Taught / Bootcamp Grad',
    'Career Switcher (Learning tech)',
    'Junior Tech Professional (Adjacent role)',
    'Experienced Professional Upskilling',
  ];

  final List<String> _experienceOptions = ['< 1 year', '1-3 years', '3+ years'];

  @override
  void initState() {
    super.initState();
    _selectedCareerId = widget.initialCareerId;
  }

  @override
  void dispose() {
    _notesController.dispose();
    _agentInputController.dispose();
    super.dispose();
  }

  void _initRatingsForCareer(Map<String, dynamic> career) {
    final skills = (career['skills'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    for (final skill in skills) {
      final id = skill['id'] as String;
      _userRatings.putIfAbsent(id, () => SkillProficiency.none);
    }
  }

  void _autofillFromProgress(Map<String, dynamic> career, WidgetRef ref) {
    final checked = ref.read(progressProvider)[career['id']] ?? <String>{};
    final skills = (career['skills'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    setState(() {
      for (var i = 0; i < skills.length; i++) {
        final id = skills[i]['id'] as String;
        // If user already made progress in this career's roadmap, promote rating
        if (checked.isNotEmpty) {
          if (i < 2) {
            _userRatings[id] = SkillProficiency.intermediate;
          } else if (i < 4) {
            _userRatings[id] = SkillProficiency.basic;
          }
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          checked.isNotEmpty
              ? 'Imported proficiency estimates from your completed roadmap milestones!'
              : 'No prior tasks found for this role yet. You can rate your skills manually below.',
        ),
      ),
    );
  }

  void _batchSetProficiency(SkillProficiency proficiency) {
    setState(() {
      for (final key in _userRatings.keys) {
        _userRatings[key] = proficiency;
      }
    });
  }

  void _generateReport(Map<String, dynamic> record) {
    final career = record['career'] as Map<String, dynamic>;
    final roadmap = record['roadmap'] as Map<String, dynamic>;
    final rawSkills = (career['skills'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    final items = rawSkills.map((s) {
      final id = s['id'] as String;
      return SkillGapItem(
        id: id,
        name: s['name'] as String,
        type: (s['type'] as String?) ?? 'core',
        requiredLevel: (s['level'] as String?) ?? 'intermediate',
        userProficiency: _userRatings[id] ?? SkillProficiency.none,
      );
    }).toList();

    final report = SkillGapReport(
      career: career,
      roadmap: roadmap,
      items: items,
      currentStatus: _currentStatus,
      yearsExperience: _yearsExperience,
      weeklyHours: _weeklyHours,
      additionalNotes: _notesController.text.trim(),
    );

    setState(() {
      _generatedReport = report;
      _currentStep = 2;
      _initAgentDiscussion(report);
    });
  }

  void _initAgentDiscussion(SkillGapReport report) {
    _agentMessages.clear();
    final topGaps = report.criticalGaps
        .take(2)
        .map((g) => g.name)
        .join(' and ');
    final initialMessage = StringBuffer()
      ..write(
        'Hello! I’ve analyzed your skills profile against **${report.career['name']}**.\n\n',
      )
      ..write(
        '• **Overall Readiness:** ${report.readinessScore}% (${report.readinessTier})\n',
      )
      ..write(
        '• **Estimated Runway:** ${report.recalibratedTimeline} at ${report.weeklyHours} hrs/week\n',
      );

    if (topGaps.isNotEmpty) {
      initialMessage.write('• **Immediate Focus Areas:** $topGaps\n\n');
      initialMessage.write(
        'Ask me below about how to bridge these gaps, portfolio project ideas, or interview questions on these skills!',
      );
    } else {
      initialMessage.write(
        '\nYou already have an exceptional match for this pathway! Ask me about portfolio specialization and interview readiness.',
      );
    }

    _agentMessages.add((fromUser: false, text: initialMessage.toString()));
  }

  Future<void> _sendAgentMessage(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty || _agentSending || _generatedReport == null) return;
    _agentInputController.clear();

    setState(() {
      _agentMessages.add((fromUser: true, text: prompt));
      _agentSending = true;
    });

    final answer = StringBuffer();
    final report = _generatedReport!;
    final career = report.career;
    final skillsContext = report.items
        .map((skill) {
          final target = skill.requiredLevel;
          final proficiency = skill.userProficiency.label;
          final kind = skill.type == 'core' ? 'core' : 'supporting';
          return '- ${skill.name}: $kind skill; target $target; learner rating $proficiency';
        })
        .join('\n');
    final roadmapContext = (report.roadmap['stages'] as List? ?? const [])
        .map((rawStage) {
          final stage = rawStage as Map<String, dynamic>;
          final title = stage['title'] ?? stage['name'] ?? 'Roadmap stage';
          final outcome = stage['outcome'] ?? stage['description'] ?? '';
          return '- $title: $outcome';
        })
        .join('\n');
    final contextPrompt =
        '''
Learner's target field/career: ${career['name']} (${career['category']})
Field overview: ${career['summary']}
Readiness Score: ${report.readinessScore}% (${report.readinessTier})
User Status: ${report.currentStatus}, Experience: ${report.yearsExperience}, Weekly Hours: ${report.weeklyHours}
Mastered Skills: ${report.masteredSkills.map((s) => s.name).join(', ')}
Critical Gaps: ${report.criticalGaps.map((s) => s.name).join(', ')}
Secondary Gaps: ${report.secondaryGaps.map((s) => s.name).join(', ')}
Target skills and learner ratings:
$skillsContext
Roadmap stages:
$roadmapContext
User Notes: ${report.additionalNotes}
Latest user question (answer this directly): $prompt
''';

    try {
      if (Firebase.apps.isNotEmpty) {
        final model = FirebaseAI.googleAI().generativeModel(
          model: 'gemini-3.8-flash',
          generationConfig: GenerationConfig(
            temperature: 0.35,
            maxOutputTokens: 500,
          ),
          systemInstruction: Content.system(
            'You are Pathfinder’s field-aware learning and skill-gap agent. '
            'Answer every user question directly and make the subject they ask about the focus of the reply. '
            'Use the learner’s stated target field/career as context, and follow a more specific field or topic they name in their question. '
            'Handle technical, conceptual, comparison, troubleshooting, learning, and career questions about that field; do not turn every reply into generic gap-closing advice. '
            'Use the supplied career, skill ratings, and roadmap facts when they help answer the actual question. '
            'Give field-specific explanations and examples, and distinguish known facts from assumptions. If a question is ambiguous, answer the likeliest interpretation and briefly state the assumption. '
            'Only recommend projects, study plans, or interview preparation when the user asks for them or they directly help answer the question. '
            'Keep replies concise (3-5 short paragraphs), structured with bullets where useful, and practical.',
          ),
        );
        await for (final response
            in model
                .generateContentStream([Content.text(contextPrompt)])
                .timeout(const Duration(seconds: 30))) {
          final chunk = response.text ?? '';
          if (chunk.isEmpty) continue;
          answer.write(chunk);
          if (!mounted) return;
          setState(() {
            if (_agentMessages.isNotEmpty && !_agentMessages.last.fromUser) {
              final last = _agentMessages.last;
              _agentMessages[_agentMessages.length - 1] = (
                fromUser: false,
                text: '${last.text}$chunk',
              );
            } else {
              _agentMessages.add((fromUser: false, text: chunk));
            }
          });
        }
        if (answer.toString().trim().isEmpty) {
          throw StateError('The AI agent returned an empty response.');
        }
        return;
      }
      throw StateError('Firebase AI not configured or empty response');
    } catch (error) {
      if (!answer.isEmpty) {
        if (mounted) {
          setState(
            () => _agentMessages.add((
              fromUser: false,
              text:
                  'The response was interrupted before it finished. Please try again for a complete answer.',
            )),
          );
        }
        return;
      }
      // Be transparent instead of substituting unrelated gap advice when AI is unavailable.
      final fallbackResponse = _generateIntelligentFallback(prompt, report);
      final errorDetail = error.toString().toLowerCase();
      final appCheckFailed =
          errorDetail.contains('app check') ||
          errorDetail.contains('appcheck');
      final availabilityNote = error is TimeoutException
          ? '\n\nThe AI service took too long to respond. Please try again in a moment.'
          : appCheckFailed
          ? '\n\nFirebase App Check rejected the AI request. Check the production App Check configuration and authorized site key.'
          : '\n\nThe AI service is unavailable right now. Check Firebase AI Logic setup and try again.';
      if (mounted) {
        setState(
          () => _agentMessages.add((
            fromUser: false,
            text: '$fallbackResponse$availabilityNote',
          )),
        );
      }
    } finally {
      if (mounted) setState(() => _agentSending = false);
    }
  }

  String _generateIntelligentFallback(String prompt, SkillGapReport report) {
    final lower = prompt.toLowerCase();
    final topGap = report.criticalGaps.isNotEmpty
        ? report.criticalGaps.first.name
        : 'core skills';

    if (lower.contains('project') || lower.contains('portfolio')) {
      return '### Recommended Bridge Project for ${report.career['name']}\n\n'
          'To prove your ability in **$topGap**, build a functional full-lifecycle application rather than tutorial clones:\n'
          '1. **Architectural Scope:** Build a service that integrates ${report.criticalGaps.take(2).map((g) => g.name).join(' with ')}.\n'
          '2. **Demonstrate Quality:** Write unit tests for core logic, use git feature branches, and include a comprehensive README with an architecture diagram.\n'
          '3. **Deployment:** Host it publicly (e.g. Firebase, Cloudflare, or Vercel) so hiring managers can interact with the live demo.';
    } else if (lower.contains('interview') ||
        lower.contains('question') ||
        lower.contains('hiring')) {
      return '### Interview Preparation Advice for $topGap\n\n'
          'In technical screenings, interviewers test your understanding of trade-offs, not just syntax:\n'
          '• **Foundational Concept:** Be ready to explain *why* you chose a specific pattern or library over alternatives.\n'
          '• **Failure Modes:** How does your system handle invalid data, network timeouts, or high load?\n'
          '• **Storytelling:** Frame your project experience using STAR (Situation, Task, Action, Result) highlighting how you overcame a bug in $topGap.';
    } else if (lower.contains('week') ||
        lower.contains('schedule') ||
        lower.contains('study')) {
      final hours = report.weeklyHours;
      final coreGaps = report.criticalGaps.take(3).map((g) => g.name).toList();
      final focus = coreGaps.isEmpty
          ? 'your next roadmap stage'
          : coreGaps.join(', ');
      final weeklyHours = (hours / 3).round();
      final practiceHours = hours - weeklyHours * 2;
      return '### A $hours-hour weekly plan for ${report.career['name']}\n\n'
          'Focus first on **$focus**. Split your time into two $weeklyHours-hour learning sessions and one $practiceHours-hour project session. '
          'Use the project session to apply the concepts, then review what you learned and update your skill ratings at the end of the week.';
    } else {
      final startingStage = report.recommendedStartingStage;
      final stageName =
          startingStage?['title'] ??
          startingStage?['name'] ??
          'the recommended starting stage';
      return 'I couldn’t reach the AI answer service, so I can’t give a reliable answer to “$prompt” right now. '
          'For your selected field, **${report.career['name']}** (${report.career['category']}), the closest profile match is **$topGap**. '
          'Your readiness is ${report.readinessScore}%, and the roadmap recommends starting at **$stageName**. '
          'Please try this question again when the AI service is available.';
    }
  }

  void _applyToJourney(SkillGapReport report) {
    final id = report.career['id'] as String;
    ref.read(progressProvider.notifier).update((all) {
      final next = <String, Set<String>>{...all};
      next.putIfAbsent(id, () => <String>{});
      Hive.box('pathfinder').put(
        'progress',
        next.map((key, value) => MapEntry(key, value.toList())),
      );
      return next;
    });

    ref.read(savedProvider.notifier).update((saved) {
      final next = {...saved, id};
      Hive.box('pathfinder').put('saved', next.toList());
      return next;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${report.career['name']} has been set as your active pathway in My Journey!',
        ),
        action: SnackBarAction(
          label: 'Go to Journey',
          onPressed: () => context.go('/journey'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(dataProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;

    return dataAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error loading careers: $err')),
      data: (data) {
        final records = data.records;
        if (records.isEmpty)
          return const Center(child: Text('No career data available'));

        _selectedCareerId ??=
            widget.initialCareerId ?? records.first['career']['id'] as String;
        final currentRecord = records.firstWhere(
          (r) => r['career']['id'] == _selectedCareerId,
          orElse: () => records.first,
        );
        final career = currentRecord['career'] as Map<String, dynamic>;

        _initRatingsForCareer(career);

        return PageFrame(
          width: 1200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(screenWidth),
              const SizedBox(height: 24),
              _buildStepIndicator(screenWidth),
              const SizedBox(height: 28),
              if (_currentStep == 0)
                _buildStep0Setup(records, currentRecord, screenWidth)
              else if (_currentStep == 1)
                _buildStep1Matrix(currentRecord, screenWidth)
              else if (_currentStep == 2 && _generatedReport != null)
                _buildStep2Report(_generatedReport!, screenWidth),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(double screenWidth) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth < 700 ? 20 : 32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff094440), Color(0xff0f766e), Color(0xff14213d)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0f766e).withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.psychology,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              pill('Interactive Skill Diagnostic Agent', color: Colors.white),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Discover Your Skill Gaps & Readiness',
            style: GoogleFonts.playfairDisplay(
              fontSize: screenWidth < 700 ? 28 : 38,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: const Text(
              'Select your desired role, rate where you currently stand on essential competencies, '
              'and get an immediate role-readiness score, customized bridging timeline, and actionable fast-track plan.',
              style: TextStyle(
                color: Color(0xffe2e8f0),
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(double screenWidth) {
    final steps = [
      ('1', 'Target & Background', Icons.flag_outlined),
      ('2', 'Rate Competencies', Icons.fact_check_outlined),
      ('3', 'Diagnostic & Agent Plan', Icons.auto_awesome),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            Expanded(
              child: InkWell(
                onTap: i < _currentStep
                    ? () => setState(() => _currentStep = i)
                    : null,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: i == _currentStep
                            ? teal
                            : i < _currentStep
                            ? const Color(0xff10b981)
                            : line,
                        child: i < _currentStep
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : Text(
                                steps[i].$1,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: i == _currentStep
                                      ? Colors.white
                                      : muted,
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      if (screenWidth > 600)
                        Flexible(
                          child: Text(
                            steps[i].$2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: i == _currentStep
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == _currentStep ? ink : muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (i < steps.length - 1)
              const Icon(Icons.chevron_right, color: line, size: 20),
          ],
        ],
      ),
    );
  }

  // STEP 0: Role Selection & Background
  Widget _buildStep0Setup(
    List<Map<String, dynamic>> records,
    Map<String, dynamic> currentRecord,
    double screenWidth,
  ) {
    final career = currentRecord['career'] as Map<String, dynamic>;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(screenWidth < 700 ? 18 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading(
              'Step 1: Choose Your Target Role & Current Status',
              size: 22,
            ),
            const SizedBox(height: 6),
            const Text(
              'Specify which career path you want to break into and your current learning starting point.',
              style: TextStyle(color: muted, fontSize: 14),
            ),
            const SizedBox(height: 28),

            // Target Role Picker
            const Text(
              'TARGET CAREER PATHWAY',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: ink,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: line, width: 1.5),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedCareerId,
                  items: records.map((r) {
                    final c = r['career'] as Map<String, dynamic>;
                    return DropdownMenuItem<String>(
                      value: c['id'] as String,
                      child: Text(
                        '${c['name']}  —  (${c['category']})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (id) {
                    if (id != null) {
                      setState(() {
                        _selectedCareerId = id;
                        _userRatings.clear();
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Role summary card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: canvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: teal, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${career['summary']} • Standard Entry: ${career['timeToEntry']?['minMonths'] ?? 6}–${career['timeToEntry']?['maxMonths'] ?? 12} months',
                      style: const TextStyle(
                        color: ink,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Current Status
            const Text(
              'CURRENT LEARNER STATUS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: ink,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _statusOptions.map((status) {
                final selected = _currentStatus == status;
                return ChoiceChip(
                  label: Text(status),
                  selected: selected,
                  selectedColor: teal.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: selected ? teal : ink,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _currentStatus = status);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Experience and Weekly commitment
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 650;
                return Flex(
                  direction: isWide ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PRIOR TECH / WORK EXPERIENCE',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 0.8,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: _experienceOptions.map((exp) {
                              final selected = _yearsExperience == exp;
                              return ChoiceChip(
                                label: Text(exp),
                                selected: selected,
                                selectedColor: teal.withValues(alpha: 0.15),
                                labelStyle: TextStyle(
                                  color: selected ? teal : ink,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                onSelected: (val) {
                                  if (val)
                                    setState(() => _yearsExperience = exp);
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    if (isWide)
                      const SizedBox(width: 24)
                    else
                      const SizedBox(height: 20),
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WEEKLY TIME COMMITMENT: $_weeklyHours HRS/WEEK',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 0.8,
                              color: ink,
                            ),
                          ),
                          Slider(
                            value: _weeklyHours.toDouble(),
                            min: 5,
                            max: 40,
                            divisions: 7,
                            activeColor: teal,
                            label: '$_weeklyHours hrs/week',
                            onChanged: (val) =>
                                setState(() => _weeklyHours = val.round()),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Additional Notes / Context
            const Text(
              'ADDITIONAL CONTEXT (OPTIONAL)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText:
                    'e.g., "I know basic Python and Git, built a couple of scripts, want to break into Backend."',
                hintStyle: const TextStyle(color: muted, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: line),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 32),

            Align(
              alignment: Alignment.centerRight,
              child: primaryButton(
                'Continue to Competency Rating',
                () => setState(() => _currentStep = 1),
                icon: Icons.arrow_forward,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // STEP 1: Skill Rating Matrix
  Widget _buildStep1Matrix(
    Map<String, dynamic> currentRecord,
    double screenWidth,
  ) {
    final career = currentRecord['career'] as Map<String, dynamic>;
    final rawSkills = (career['skills'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    final coreSkills = rawSkills
        .where((s) => (s['type'] as String?) == 'core')
        .toList();
    final secondarySkills = rawSkills
        .where((s) => (s['type'] as String?) != 'core')
        .toList();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(screenWidth < 700 ? 18 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading(
                        'Step 2: Rate Your Current Skill Levels',
                        size: 22,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Be honest! Rate where you currently stand for ${career['name']}. This generates your customized gap report.',
                        style: const TextStyle(color: muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _autofillFromProgress(career, ref),
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Auto-fill from Journey'),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Quick Batch Action Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: canvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: line),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Quick shortcuts: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: ink,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _batchSetProficiency(SkillProficiency.none),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Set All None',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _batchSetProficiency(SkillProficiency.basic),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Set All Basic',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _batchSetProficiency(SkillProficiency.intermediate),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Set All Hands-on',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // CORE COMPETENCIES
            _buildSkillGroupHeader(
              'Core Competencies (${coreSkills.length})',
              'Must-have fundamentals and primary requirements for entry-level hiring.',
              const Color(0xff0f766e),
            ),
            const SizedBox(height: 12),
            for (final s in coreSkills) _buildSkillRow(s, screenWidth),

            const SizedBox(height: 28),

            // SECONDARY COMPETENCIES
            if (secondarySkills.isNotEmpty) ...[
              _buildSkillGroupHeader(
                'Secondary & Applied Tooling (${secondarySkills.length})',
                'Supplemental skills, frameworks, and workflows that set candidates apart.',
                const Color(0xff475569),
              ),
              const SizedBox(height: 12),
              for (final s in secondarySkills) _buildSkillRow(s, screenWidth),
            ],

            const SizedBox(height: 36),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _currentStep = 0),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back to Setup'),
                ),
                primaryButton(
                  'Run Skill Gap Analysis',
                  () => _generateReport(currentRecord),
                  icon: Icons.analytics_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillGroupHeader(String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: line, width: 1.5)),
      ),
      child: Row(
        children: [
          Container(width: 4, height: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: ink,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillRow(Map<String, dynamic> skill, double screenWidth) {
    final id = skill['id'] as String;
    final name = skill['name'] as String;
    final level = (skill['level'] as String?) ?? 'intermediate';
    final currentVal = _userRatings[id] ?? SkillProficiency.none;
    final isCompact = screenWidth < 750;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: currentVal != SkillProficiency.none
              ? currentVal.color.withValues(alpha: 0.3)
              : line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: line.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Target: $level',
                  style: const TextStyle(
                    fontSize: 11,
                    color: muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Rating segmented selector
          if (isCompact)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: SkillProficiency.values.map((prof) {
                final selected = currentVal == prof;
                return ChoiceChip(
                  avatar: Icon(
                    prof.icon,
                    size: 14,
                    color: selected ? Colors.white : prof.color,
                  ),
                  label: Text(prof.label),
                  selected: selected,
                  selectedColor: prof.color,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : ink,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _userRatings[id] = prof);
                  },
                );
              }).toList(),
            )
          else
            Row(
              children: SkillProficiency.values.map((prof) {
                final selected = currentVal == prof;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () => setState(() => _userRatings[id] = prof),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? prof.color : canvas,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? prof.color : line,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              prof.icon,
                              size: 14,
                              color: selected ? Colors.white : prof.color,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                prof.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected ? Colors.white : ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // STEP 2: Diagnostic Report & Agent Interaction
  Widget _buildStep2Report(SkillGapReport report, double screenWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Scorecard
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(screenWidth < 700 ? 20 : 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                children: [
                  // Gauge / Score
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: report.tierColor.withValues(alpha: 0.12),
                          border: Border.all(color: report.tierColor, width: 6),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${report.readinessScore}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 26,
                                  color: report.tierColor,
                                ),
                              ),
                              const Text(
                                'MATCH',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: report.tierColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              report.readinessTier,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            report.career['name'],
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: ink,
                            ),
                          ),
                          Text(
                            'Based on ${report.items.length} role competencies',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isWide) const Spacer() else const SizedBox(height: 20),

                  // Recalibrated Timeline Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xfff0fdf4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xffbbf7d0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 16,
                              color: Color(0xff166534),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'RECALIBRATED RUNWAY',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xff166534),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          report.recalibratedTimeline,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xff166534),
                          ),
                        ),
                        Text(
                          'Estimated for ${report.weeklyHours} hours/week',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xff15803d),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // Action CTA Bar: Apply to Journey
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xffecfdf5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xffa7f3d0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt, color: Color(0xff059669), size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Save this Fast-Track Roadmap to My Journey',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xff065f46),
                      ),
                    ),
                    Text(
                      'Auto-saves ${report.career['name']} and tracks your gap-closing progress.',
                      style: const TextStyle(
                        color: Color(0xff047857),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _applyToJourney(report),
                icon: const Icon(Icons.bookmark_add, size: 16),
                label: const Text('Apply Plan'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff059669),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Skill Breakdown Cards (Strengths vs Gaps)
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 750;
            return Flex(
              direction: isWide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Critical Gaps
                Expanded(
                  flex: isWide ? 1 : 0,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xffe11d48),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Critical Skill Gaps (${report.criticalGaps.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'High-priority core competencies you must build to pass screenings.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          const SizedBox(height: 14),
                          if (report.criticalGaps.isEmpty)
                            const Text(
                              'No critical core gaps identified! You have solid baseline fundamentals.',
                              style: TextStyle(
                                color: Color(0xff059669),
                                fontSize: 13,
                              ),
                            )
                          else
                            for (final gap in report.criticalGaps)
                              _buildGapPill(
                                gap,
                                const Color(0xfffee2e2),
                                const Color(0xff991b1b),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (isWide)
                  const SizedBox(width: 16)
                else
                  const SizedBox(height: 16),

                // Strengths
                Expanded(
                  flex: isWide ? 1 : 0,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                color: Color(0xff059669),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Mastered Strengths (${report.masteredSkills.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Competencies you already meet. Highlight these on your resume!',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          const SizedBox(height: 14),
                          if (report.masteredSkills.isEmpty)
                            const Text(
                              'None yet! Starting from scratch is completely normal.',
                              style: TextStyle(color: muted, fontSize: 13),
                            )
                          else
                            for (final s in report.masteredSkills)
                              _buildGapPill(
                                s,
                                const Color(0xffdcfce7),
                                const Color(0xff166534),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // Roadmap Fast-Track Suggestions
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading('Your Fast-Track Bridging Blueprint', size: 18),
                const SizedBox(height: 6),
                const Text(
                  'How to tailor Pathfinder’s roadmap to your current background without wasting time.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 16),

                if (report.skippableStages.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: canvas,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: line),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fast_forward, color: teal, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Recommended Stages to Fast-Forward: ${report.skippableStages.join(', ')}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xfff0fdfa),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xff99f6e4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flag, color: teal, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Recommended Starting Point: ${report.recommendedStartingStage?['name'] ?? 'Stage 1'} (${(report.recommendedStartingStage?['tasks'] as List? ?? []).length} focused tasks)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xff0f766e),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            context.go('/career/${report.career['id']}'),
                        child: const Text('View Full Roadmap'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // AI Skill Gap Consultant Chat
        _buildAgentChatSection(report),

        const SizedBox(height: 24),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _currentStep = 1),
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Adjust Skill Self-Ratings'),
          ),
        ),
      ],
    );
  }

  Widget _buildGapPill(SkillGapItem item, Color bgColor, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(item.userProficiency.icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: textColor,
              ),
            ),
          ),
          Text(
            'Current: ${item.userProficiency.label}',
            style: TextStyle(
              fontSize: 11,
              color: textColor.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentChatSection(SkillGapReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, color: teal, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading('Ask the Skill Gap Diagnostic Agent', size: 18),
                      Text(
                        'Ask any question about ${report.career['name']} or ${report.career['category']}; answers use your skill profile and roadmap.',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quick Prompt Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text(
                    'Bridging project idea',
                    style: TextStyle(fontSize: 12),
                  ),
                  avatar: const Icon(Icons.lightbulb_outline, size: 14),
                  onPressed: () => _sendAgentMessage(
                    'What is a single project I can build to bridge my top skill gaps?',
                  ),
                ),
                ActionChip(
                  label: const Text(
                    'Interview questions to prepare',
                    style: TextStyle(fontSize: 12),
                  ),
                  avatar: const Icon(Icons.help_outline, size: 14),
                  onPressed: () => _sendAgentMessage(
                    'What technical interview questions will employers ask regarding my missing skills?',
                  ),
                ),
                ActionChip(
                  label: const Text(
                    'Weekly study breakdown',
                    style: TextStyle(fontSize: 12),
                  ),
                  avatar: const Icon(Icons.calendar_today, size: 14),
                  onPressed: () => _sendAgentMessage(
                    'Give me a weekly study schedule for my $_weeklyHours hours/week to close these gaps quickly.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Message Stream
            Container(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _agentMessages.length,
                itemBuilder: (context, index) {
                  final msg = _agentMessages[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: msg.fromUser ? const Color(0xffe7f3ef) : canvas,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: msg.fromUser ? const Color(0xff99f6e4) : line,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              msg.fromUser ? Icons.person : Icons.auto_awesome,
                              size: 14,
                              color: msg.fromUser
                                  ? teal
                                  : const Color(0xff0284c7),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              msg.fromUser
                                  ? 'You'
                                  : 'Skill Gap Diagnostic Agent',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: msg.fromUser
                                    ? teal
                                    : const Color(0xff0284c7),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          msg.text,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            if (_agentSending) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Agent is analyzing your profile...',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            // Chat Input Field
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _agentInputController,
                    decoration: InputDecoration(
                      hintText:
                          'Ask about ${report.career['name']} or its field...',
                      hintStyle: const TextStyle(color: muted, fontSize: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: line),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (val) => _sendAgentMessage(val),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _agentSending
                      ? null
                      : () => _sendAgentMessage(_agentInputController.text),
                  icon: const Icon(Icons.send, color: teal),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
