import 'package:flutter/material.dart';

import 'assistant_models.dart';
import 'offline_text.dart';

/// One written answer and the phrases that ask for it.
class GuideTopic {
  const GuideTopic(
    this.id,
    this.phrases,
    this.text, {
    this.chips = const [],
    this.needsCue = true,
    this.requires = const [],
  });
  final String id;
  final List<String> phrases;
  final String text;
  final List<Suggestion> chips;

  /// Whether a bare mention ("subjects") is too vague on its own and needs a
  /// question around it ("how do I add a subject"). Short messages that are
  /// nothing but the feature's name ("dark mode") are always accepted.
  final bool needsCue;

  /// Words of which at least one must also appear. Worry about an exam gets
  /// exam advice; worry about anything else does not.
  final List<String> requires;
}

/// Written answers about how FocusForge works, and study-habit coaching.
///
/// Both are fixed text chosen by phrase, like the lesson library: no model,
/// no network, nothing about the user leaves the conversation. App answers
/// are checked before lessons, because a feature name is never a school
/// topic; habit coaching is checked after them, so "how to make notes" still
/// reaches the notes lesson.
abstract final class OfflineGuide {
  static const _shield = Suggestion(
    Copy('Open Shield'),
    Icons.shield_outlined,
    AssistantAction(Act.openShield),
  );
  static const _lock = Suggestion(
    Copy('Lock distracting apps'),
    Icons.lock_outline_rounded,
    AssistantAction(Act.lock),
  );
  static const _focus = Suggestion(
    Copy('Add a subject'),
    Icons.add_rounded,
    AssistantAction(Act.openFocus),
  );
  static const _start = Suggestion(
    Copy('Start a block'),
    Icons.play_arrow_rounded,
    AssistantAction(Act.focusNow),
  );
  static const _plan = Suggestion(
    Copy('Plan my study'),
    Icons.event_note_rounded,
    AssistantAction(Act.plan),
  );
  static const _report = Suggestion(
    Copy('My report'),
    Icons.insights_rounded,
    AssistantAction(Act.report),
  );
  static const _timetable = Suggestion(
    Copy('Make a timetable'),
    Icons.view_timeline_outlined,
    AssistantAction(Act.timetable),
  );
  static const _distractions = Suggestion(
    Copy('What’s distracting me?'),
    Icons.phone_android_rounded,
    AssistantAction(Act.distractions),
  );
  static const _board = Suggestion(
    Copy('Open leaderboard'),
    Icons.leaderboard_outlined,
    AssistantAction(Act.openLeaderboard),
  );

  /// Words that turn a feature's name into a question about it.
  static const _cues = [
    'how',
    'what',
    'whats',
    'where',
    'why',
    'which',
    'is',
    'are',
    'does',
    'do',
    'can',
    'explain',
    'use',
    'using',
    'work',
    'works',
    'working',
    'turn on',
    'turn off',
    'enable',
    'disable',
    'set up',
    'setup',
    'change',
    'add',
    'join',
    'create',
    'delete',
    'remove',
    'find',
    'open',
    'help',
    'mean',
    'meaning',
    'kya',
    'kaise',
    'kaha',
    'kahan',
    'batao',
    'samjhao',
  ];

  static const appTopics = <GuideTopic>[
    GuideTopic(
      'strict',
      ['strict mode', 'strict lock', 'lock in mode'],
      'Strict Mode locks your Shield rules for a length you choose, from 15 minutes to 8 hours, so you cannot loosen them on impulse.\n\n'
          'Set your app rules in Shield first, then open You → Strict Mode, pick the length and type the commitment phrase. Ending early takes three steps: type the phrase, wait out a short countdown, then confirm. Phone calls and emergency services always stay reachable.',
      chips: [_shield],
    ),
    GuideTopic(
      'breath',
      [
        'breath gate',
        'breathing gate',
        'deep breath gate',
        'breathing pause',
        'breathe first',
        'breathing screen',
      ],
      'The Breath Gate is a short breathing pause between an impulse and a blocked app.\n\n'
          'When an app on your Shield list is closed, the block screen offers “Pause and breathe first”. You follow a circle through three 4-7-8 breaths (in for 4, hold for 7, out for 8). Afterwards you choose: walk away, or go in for a short grace period. Each choice is counted on the Shield screen, so you can see how often the pause changed your mind.',
      chips: [_shield],
    ),
    GuideTopic(
      'shield',
      ['shield', 'app blocking', 'app blocker', 'blocking work', 'blocker'],
      'Shield keeps the apps you choose out of the way while you study. It runs on your Android phone.\n\n'
          'Open the Shield tab and give each app a rule: Focus only (closed during focus blocks), Blocked (closed all the time), or a daily time budget. Shield needs Usage Access and permission to draw over other apps; it asks for them when you first add a rule. You can also tell me “block Instagram”.',
      chips: [_shield, _lock],
    ),
    GuideTopic(
      'shorts',
      [
        'shorts',
        'youtube shorts',
        'youtube study mode',
        'youtube filter',
        'youtube filters',
        'study mode',
        'youtube feed',
        'block home and search',
      ],
      'Block Shorts closes YouTube Shorts while ordinary videos keep playing.\n\n'
          'Open Shield → YouTube filters and switch on Block Shorts. You can also close YouTube’s home feed and search. These filters use Android Accessibility only to recognise YouTube screens; that check stays on your phone.',
      chips: [_shield],
    ),
    GuideTopic(
      'budget',
      [
        'time budget',
        'time budgets',
        'daily allowance',
        'app budget',
        'app limit',
        'app limits',
        'time limit',
        'usage limit',
      ],
      'A time budget gives an app a daily allowance; when it runs out, Shield closes the app until tomorrow.\n\n'
          'Open Shield, choose the app, pick “Daily allowance” and set the minutes. Budgets count only after you allow app usage access.',
      chips: [_shield],
    ),
    GuideTopic(
      'subject',
      [
        'add a subject',
        'add subject',
        'new subject',
        'add subjects',
        'delete a subject',
        'delete subject',
        'remove a subject',
        'remove subject',
        'rename subject',
        'edit subject',
        'manage subjects',
        'subject add',
      ],
      'Subjects live on the Focus tab.\n\n'
          'Open Focus, tap the subject picker above the timer and choose “Add subject”. Give it a name, an icon and a colour. “Manage subjects” in the same place lets you rename or remove one. Time you log under a subject shows up in your reports.',
      chips: [_focus],
      needsCue: false,
    ),
    GuideTopic(
      'timer',
      [
        'timer',
        'focus timer',
        'pomodoro presets',
        'block length',
        'break length',
        'custom plan',
        'full screen clock',
        'fullscreen clock',
      ],
      'The focus timer is on the Focus tab.\n\n'
          'Pick a subject and a plan (Pomodoro presets, or “Custom plan” for your own block and break lengths), then tap Start. You can pause, skip a block or open the clock full screen. Every completed block earns XP and counts toward your goal. I can also start one for you.',
      chips: [_start],
    ),
    GuideTopic(
      'groups',
      [
        'study group',
        'study groups',
        'group code',
        'join a group',
        'join group',
        'create a group',
        'create group',
      ],
      'Study groups share one weekly goal with friends.\n\n'
          'Open You → Study Groups. Create a group and share its code, or choose “Join with code”. Everyone’s completed focus minutes count toward the group goal, and standings are visible only to members. Groups need a linked account.',
    ),
    GuideTopic(
      'clock',
      [
        'clock face',
        'clock faces',
        'clock style',
        'timer style',
        'clock design',
        'timer design',
      ],
      'You can change how the focus clock looks.\n\n'
          'Open You → Appearance → Clock face and pick a style. The timer works the same with every face.',
      needsCue: false,
    ),
    GuideTopic(
      'theme',
      [
        'dark mode',
        'light mode',
        'dark theme',
        'light theme',
        'app theme',
        'change theme',
        'change the theme',
        'theme change',
        'accent color',
        'accent colour',
        'app color',
        'app colour',
        'true black',
        'amoled',
      ],
      'Theme and colours are under You → Appearance.\n\n'
          'Choose Light, Dark or follow the system, then pick an accent colour. In dark mode you can switch on True black for OLED screens.',
      needsCue: false,
    ),
    GuideTopic(
      'badges',
      ['achievement', 'achievements', 'badge', 'badges'],
      'Achievements are badges for milestones such as total focus time, streaks and finished blocks.\n\n'
          'Open You → Achievements to see what you have earned and what is next. They unlock on their own as you study.',
    ),
    GuideTopic(
      'xp',
      [
        'xp',
        'level up',
        'levels work',
        'my level',
        'experience points',
        'earn xp',
        'get xp',
      ],
      'One XP is one focused minute in a completed block.\n\n'
          'XP fills the bar on your profile; each level needs a little more than the last, up to level 50. Blocks you abandon still count toward your totals but do not earn XP.',
      chips: [_start],
    ),
    GuideTopic(
      'account',
      [
        'delete my account',
        'delete account',
        'sign out',
        'log out',
        'logout',
        'backup',
        'back up',
        'restore my data',
        'sync my data',
        'new phone',
        'link account',
        'link my account',
        'sign in',
        'login',
        'log in',
        'export my data',
      ],
      'Account options are under You → Account.\n\n'
          'Link a Google or email account there to back up your progress privately and restore it on a new phone. The same screen lets you sign out (your history stays on this device), export all your data, or permanently delete your account.',
      needsCue: false,
    ),
    GuideTopic(
      'privacy',
      [
        'privacy',
        'my data',
        'data private',
        'data safe',
        'data stored',
        'data collected',
        'is my data',
        'track me',
        'tracking me',
      ],
      'Your study history is stored on your phone.\n\n'
          'Without a linked account nothing is uploaded. With one, a private backup is kept so you can restore on a new phone. Your name and weekly hours appear on the leaderboard only if you turn on sharing, and in groups only to members. You → Account shows what is in the cloud, lets you export everything as JSON, and can delete your account. I answer offline unless you turn on the optional Cloud Study Coach.',
    ),
    GuideTopic(
      'sounds',
      [
        'ambient',
        'ambient sound',
        'ambient sounds',
        'rain sound',
        'rain sounds',
        'white noise',
        'brown noise',
        'background sound',
        'background sounds',
        'background music',
        'focus music',
        'study music',
        'focus sounds',
      ],
      'Ambient sounds are on the Focus tab, under Ambient mix.\n\n'
          'Tap Rain, Forest, Café, Waves, Fireplace or Brown Noise to play them, mix several, and set each one’s level. “Stop all” turns them off.',
      chips: [_start],
      needsCue: false,
    ),
    GuideTopic(
      'notifications',
      [
        'quiet hours',
        'notification settings',
        'notifications',
        'streak alert',
        'streak alerts',
        'turn off notifications',
      ],
      'Notification settings are under You → Notifications.\n\n'
          'Choose session reminders, streak alerts and the running-timer notification, and set Quiet hours so nothing arrives overnight. To set a reminder, just tell me, for example “remind me to revise physics at 6 pm”.',
    ),
    GuideTopic(
      'widgets',
      ['widget', 'widgets', 'home screen widget', 'home screen widgets'],
      'FocusForge has home-screen widgets.\n\n'
          'Long-press an empty spot on your phone’s home screen, choose Widgets, find FocusForge and drag one out. They show your progress and timer without opening the app.',
    ),
    GuideTopic(
      'permissions',
      [
        'usage access',
        'overlay permission',
        'accessibility permission',
        'app access',
        'permissions',
        'permission',
      ],
      'App permissions are under You → App access.\n\n'
          'Usage Access lets Shield see which app is open and count screen time. “Display over other apps” lets it cover a closed app. Accessibility is only for the optional YouTube filters. Each is asked for only when a feature needs it.',
      chips: [_shield],
    ),
    GuideTopic(
      'leaderboard-how',
      ['leaderboard work', 'leaderboard works', 'how is rank', 'rank work'],
      'The leaderboard is a weekly board of people who choose to share their focus time.\n\n'
          'Open You → Leaderboard and turn on “Share my weekly score” to appear. Signed-in users then see your display name, level and this week’s focus hours; turn sharing off any time. It starts fresh each week and needs a linked account.',
      chips: [_board],
    ),
  ];

  static const habitTopics = <GuideTopic>[
    GuideTopic(
      'revise-exam',
      [
        'revise before',
        'revise for',
        'how to revise',
        'how do i revise',
        'how should i revise',
        'revision kaise',
        'revision tips',
        'revision strategy',
        'how to do revision',
        'prepare for exam',
        'prepare for exams',
        'prepare for my exam',
        'prepare for the exam',
        'study for exam',
        'study for exams',
        'study for my exam',
        'study for an exam',
        'study for the exam',
        'exam preparation tips',
        'exam ki taiyari',
        'exam ki tayari',
      ],
      'Revise by testing yourself, not by rereading.\n\n'
          '1. List every topic and mark it green, amber or red.\n'
          '2. Spend most time on amber and red, in short blocks.\n'
          '3. Each block: close the book, write what you remember, then check and fix gaps.\n'
          '4. Do past papers under time, and keep an error log of every mistake.\n'
          '5. Revisit each topic again after a day, a few days and a week.\n'
          'In the last day, review your error log and sleep well instead of learning new chapters.',
      chips: [_timetable, _plan],
      needsCue: false,
    ),
    GuideTopic(
      'exam-stress',
      [
        'stressed about',
        'stress about',
        'anxious about',
        'nervous about',
        'worried about',
        'scared about',
        'afraid of',
        'tensed about',
        'tension about',
        'scared',
        'nervous',
        'anxious',
        'stressed',
        'stress',
        'tension',
        'scared of exam',
        'scared of exams',
        'scared of my exam',
        'afraid of exam',
        'exam fear',
        'fear of exam',
        'fear of exams',
        'exam tension',
        'exam ka darr',
        'exam ka dar',
        'exam se darr',
        'exam se dar',
        'darr lag',
        'dar lag',
        'tension ho',
        'ghabrahat',
        'ghabra raha',
        'ghabra rahi',
      ],
      'Feeling nervous before exams is normal, and it usually means you care.\n\n'
          'Right now: breathe in for 4, hold for 7, out for 8, three times. Then write down the one thing worrying you most and one small step you can take today, such as one 25-minute block on a weak topic. Practising with past papers makes the real exam feel familiar. Keep sleeping, eating and moving normally.\n\n'
          'If the worry feels too heavy or does not ease, talk to someone you trust: a parent, teacher, friend or counsellor.',
      chips: [_start, _plan],
      needsCue: false,
      requires: [
        'exam',
        'exams',
        'test',
        'tests',
        'paper',
        'papers',
        'result',
        'results',
        'marks',
        'board',
        'boards',
        'pariksha',
        'neet',
        'jee',
      ],
    ),
    GuideTopic(
      'setback',
      [
        'failed my',
        'failed in',
        'failed the',
        'i failed',
        'fail ho gaya',
        'fail ho gayi',
        'low marks',
        'bad marks',
        'poor marks',
        'less marks',
        'kam marks',
        'marks kam',
        'bad result',
        'bad results',
        'bad grade',
        'bad grades',
        'low score',
        'scored less',
        'did badly',
        'did bad',
        'messed up my exam',
        'messed up my test',
      ],
      'One result is information, not a verdict on you.\n\n'
          'When you are ready, go through the paper and label each lost mark: did not know it, forgot it, misread it, or ran out of time. Pick the two biggest causes and plan short blocks on them this week. Then try a few similar questions to see the change. Many people improve a lot from exactly this kind of review.',
      chips: [_plan, _report],
      needsCue: false,
    ),
    GuideTopic(
      'no-mood',
      [
        'dont feel like',
        'do not feel like',
        'not in the mood',
        'dont want to study',
        'do not want to study',
        'mann nahi',
        'padhai me mann',
        'padhne ka mann',
        'dil nahi',
        'no mood to study',
        'cant start studying',
        'cannot start studying',
      ],
      'You do not have to feel like it to start. Starting usually brings the mood.\n\n'
          'Make the first step tiny: open one book to one page and set a 10-minute block. If you still want to stop after 10 minutes, stop. Most of the time you will keep going. Put your phone in another room first.',
      chips: [_start],
      needsCue: false,
    ),
    GuideTopic(
      'hours',
      [
        'how many hours should',
        'how much should i study',
        'how long should i study',
        'hours should i study',
        'hours a day should',
        'kitne ghante padhna',
        'kitne ghante padhu',
        'kitne ghante padhe',
        'how much time should i study',
      ],
      'Steady focused hours beat long distracted ones.\n\n'
          'A sustainable start for most students is 2 to 4 focused hours on school days and a little more before exams, in 25 to 50 minute blocks with breaks. Start from what you can do now and add 15 to 30 minutes a week. Quality matters most: a block where you test yourself is worth more than an hour of rereading. Keep 7 to 9 hours of sleep.',
      chips: [_plan, _timetable],
      needsCue: false,
    ),
    GuideTopic(
      'night',
      [
        'study at night',
        'study in the night',
        'night study',
        'study late at night',
        'raat ko padh',
        'night owl',
        'morning or night',
        'night or morning',
        'study in the morning',
        'best time to study',
        'subah padh',
      ],
      'The best time to study is the time you can protect every day.\n\n'
          'Morning works well for hard new material for many people; evening suits review. Night study is fine if you still get 7 to 9 hours of sleep and keep a regular bedtime, because memory is consolidated during sleep. Avoid trading sleep for extra hours before an exam.',
      chips: [_report, _plan],
      needsCue: false,
    ),
    GuideTopic(
      'sleep',
      [
        'how much sleep',
        'sleep do i need',
        'hours of sleep',
        'sleep schedule',
        'neend nahi',
        'kitna sona',
        'kitni neend',
        'cant sleep',
        'cannot sleep',
      ],
      'Most teenagers need about 8 to 10 hours of sleep, and adults about 7 to 9.\n\n'
          'Sleep is when the day’s learning gets stored, so cutting it costs more than it saves. Keep the same bedtime and wake time, put screens away 30 minutes before bed, and avoid caffeine late in the day. If poor sleep goes on for weeks, talk to a parent or doctor.',
      needsCue: false,
    ),
    GuideTopic(
      'time-management',
      [
        'manage time',
        'manage my time',
        'time management',
        'time manage',
        'manage my day',
        'time ka use',
        'time kaise manage',
      ],
      'Plan the day before it starts, in blocks.\n\n'
          '1. Write the three most important tasks for tomorrow.\n'
          '2. Give each one a fixed block on your timetable, hardest first.\n'
          '3. Work in focus blocks with short breaks, phone away.\n'
          '4. At night, check what got done and move the rest.\n'
          'I can build a timetable or a plan for today.',
      chips: [_timetable, _plan],
      needsCue: false,
    ),
    GuideTopic(
      'pomodoro',
      [
        'what is pomodoro',
        'what is the pomodoro',
        'what is a pomodoro',
        'pomodoro technique',
        'pomodoro method',
        'pomodoro kya',
        'explain pomodoro',
        'how does pomodoro',
        'how pomodoro works',
      ],
      'The Pomodoro technique is focused work in short timed blocks with breaks.\n\n'
          'Classic version: 25 minutes of focus, a 5-minute break, and a longer 15 to 30 minute break after four blocks. During a block you do one task and nothing else. The Focus tab has Pomodoro presets, or set your own lengths.',
      chips: [_start],
      needsCue: false,
    ),
    GuideTopic(
      'reading',
      [
        'read faster',
        'reading speed',
        'speed reading',
        'read quickly',
        'read fast',
        'read more quickly',
      ],
      'For study, understanding beats speed.\n\n'
          'Before reading a chapter, skim the headings, summary and questions so you know what to look for. Read with a question in mind, then close the book and recall the main points in a few lines. With practice your reading gets faster because you know what matters. Pure speed-reading tricks usually cut understanding.',
      needsCue: false,
    ),
    GuideTopic(
      'phone',
      [
        'stop using my phone',
        'stop using phone',
        'stop checking my phone',
        'keep my phone away',
        'put my phone away',
        'phone away',
        'use my phone less',
        'phone se door',
        'phone chhod',
        'mobile chhod',
        'phone kam',
        'mobile kam',
      ],
      'Make the phone harder to reach, not harder to resist.\n\n'
          'Put it in another room or a drawer during a block. Turn off non-urgent notifications. Use Shield to close your most distracting apps during focus blocks, or give them a daily time budget. Check it only in your breaks.',
      chips: [_lock, _distractions],
      needsCue: false,
    ),
    GuideTopic(
      'wake-early',
      [
        'wake up early',
        'wake early',
        'get up early',
        'waking up early',
        'subah jaldi',
        'jaldi uth',
        'jaldi utha',
      ],
      'Waking early starts the night before.\n\n'
          'Move your bedtime and alarm 15 minutes earlier every few days instead of all at once. Keep the alarm across the room, open the curtains or get light soon after waking, and plan an easy first task. Keep the same times at weekends.',
      needsCue: false,
    ),
    GuideTopic(
      'consistency',
      [
        'be consistent',
        'stay consistent',
        'become consistent',
        'consistency tips',
        'be regular',
        'stay regular',
        'regular rehna',
        'stay disciplined',
        'be disciplined',
        'build discipline',
        'self discipline',
        'study daily',
        'study every day',
        'study habit',
        'study habits',
      ],
      'Consistency comes from a small plan you can repeat on a bad day.\n\n'
          'Set a daily minimum that feels almost too easy, such as one 25-minute block, at the same time and place each day. Do it even when busy; anything more is a bonus. Your streak on Home shows the chain, and missing one day is fine as long as you do not miss two.',
      chips: [_start, _plan],
      needsCue: false,
    ),
    GuideTopic(
      'long-hours',
      [
        'study for long hours',
        'study for long',
        'long hours',
        'study longer',
        'sit for long',
        'focus for long',
        'study for hours',
        'zyada der padh',
        'lambe samay',
      ],
      'Build long study days out of short blocks.\n\n'
          'Work in 25 to 50 minute blocks with 5 to 10 minute breaks; stand up, drink water and look away from screens in the breaks. Switch subjects every block or two. Grow the total gradually, by about 15 to 30 minutes a week. Stop when your recall drops: tired hours teach little.',
      chips: [_timetable, _start],
      needsCue: false,
    ),
    GuideTopic(
      'study-method',
      [
        'study kaise kare',
        'study kaise karu',
        'padhai kaise kare',
        'padhai kaise karu',
        'padhai kaise karein',
        'kaise padhe',
        'kaise padhu',
        'how to study effectively',
        'how to study properly',
        'how should i study',
        'how do i study',
        'best way to study',
        'study effectively',
        'study smart',
        'study smarter',
      ],
      'Study in short focused blocks and test yourself in every one.\n\n'
          '1. Pick one topic and one outcome for the block.\n'
          '2. Learn it from your book or notes for 20 to 30 minutes, phone away.\n'
          '3. Close the book and write or say what you remember.\n'
          '4. Check, fix gaps, and do a few practice questions.\n'
          '5. Revisit it after a day, a few days and a week.\n'
          'Ask me to explain a topic or quiz you on it any time.',
      chips: [_plan, _start],
      needsCue: false,
    ),
  ];

  /// Subject-specific advice for "how to study maths" and the like.
  static const _subjectAdvice = <(List<String>, String)>[
    (
      ['maths', 'math', 'mathematics', 'algebra', 'geometry', 'calculus'],
      'Maths is learned by solving, not reading.\n\n'
          'Read the worked example, then cover it and solve it yourself. Do several problems of each type, starting easy. Keep a formula sheet and a mistake log, and redo every wrong question a few days later. Mix question types once each one feels comfortable.',
    ),
    (
      ['physics'],
      'In physics, understand the idea, then practise problems.\n\n'
          'For each topic, explain the concept in your own words, learn the formulas with their units, and solve numericals step by step: list knowns, pick the formula, then calculate. Draw a diagram for every problem. Redo the ones you get wrong.',
    ),
    (
      ['chemistry'],
      'Chemistry has three parts, and each needs a different approach.\n\n'
          'Physical chemistry: practise numericals like maths. Inorganic: make short tables and recall them often. Organic: learn the reaction mechanisms and practise converting one compound into another. Write equations out by hand.',
    ),
    (
      ['biology', 'bio'],
      'In biology, draw it and explain it.\n\n'
          'Make labelled diagrams from memory, then check them. Turn each heading into a question and answer it aloud. Learn the key terms precisely, and connect structures to their functions. Revise with spaced recall.',
    ),
    (
      [
        'history',
        'geography',
        'civics',
        'political science',
        'social science',
        'social studies',
        'sst',
        'economics',
      ],
      'For history, geography and social science, build a story, then recall it.\n\n'
          'Make a timeline or a one-page map of each chapter: causes, events, effects and key terms. Close the book and rewrite it from memory. Practise answering past questions in the word limit, with points and examples.',
    ),
    (
      ['english', 'hindi', 'language', 'grammar', 'literature'],
      'For languages, read, write and practise a little every day.\n\n'
          'For literature, know the themes, characters and a few short quotes for each text. For grammar, learn the rule and do exercises. Practise writing tasks to time and compare them with model answers.',
    ),
  ];

  static const _subjectLead = [
    'how to study',
    'how do i study',
    'how should i study',
    'how to prepare',
    'how to learn',
    'how to get better at',
    'how to improve in',
    'how to improve at',
    'how to improve my',
    'how to score in',
    'how to score good marks in',
    'tips for',
    'tips to study',
  ];

  /// An app question ("how do I use strict mode", "dark mode").
  static GuideTopic? app(String input) {
    final text = OfflineText.normalize(input);
    if (text.isEmpty || text.length > OfflineText.maxInputLength) return null;
    final words = text.split(' ').length;
    final cue = OfflineText.any(text, _cues);
    for (final topic in appTopics) {
      for (final phrase in topic.phrases) {
        if (!OfflineText.has(text, phrase)) continue;
        final bare = words <= phrase.split(' ').length + 1;
        if (cue || bare || !topic.needsCue) return topic;
      }
    }
    return null;
  }

  /// A study-habit question ("how to revise before exams").
  static GuideTopic? habit(String input) {
    final text = OfflineText.normalize(input);
    if (text.isEmpty || text.length > OfflineText.maxInputLength) return null;
    // A plan or timetable request is an action Pip takes, not advice.
    if (OfflineText.any(text, const [
      'plan',
      'planner',
      'timetable',
      'time table',
      'schedule',
      // Dated exam questions get the coach's countdown-aware answer.
      'exam tomorrow',
      'exam today',
      'last minute',
    ])) {
      return null;
    }
    if (OfflineText.any(text, _subjectLead)) {
      for (final (names, advice) in _subjectAdvice) {
        if (OfflineText.any(text, names)) {
          return GuideTopic('subject-method', names, advice, chips: [_start]);
        }
      }
    }
    for (final topic in habitTopics) {
      if (OfflineText.any(text, topic.phrases) &&
          (topic.requires.isEmpty || OfflineText.any(text, topic.requires))) {
        return topic;
      }
    }
    return null;
  }

  static AssistantReply reply(GuideTopic topic) =>
      AssistantReply([Say(Copy.raw(topic.text))], suggestions: topic.chips);
}
