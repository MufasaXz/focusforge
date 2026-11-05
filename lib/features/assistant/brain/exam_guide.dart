import 'package:flutter/foundation.dart';

/// What Pip knows about one Indian entrance or board exam.
///
/// The facts are the stable parts of each exam — who runs it, what it covers,
/// how it is marked — and never a date, because dates move every year. Every
/// card says to check the official notice, since patterns do change too.
@immutable
class ExamInfo {
  const ExamInfo({
    required this.id,
    required this.name,
    required this.summary,
    required this.pattern,
    required this.marking,
    required this.tip,
    this.subjects = const [],
  });

  final String id;

  /// The exam's proper name, shown as written in every language.
  final String name;
  final String summary;
  final String pattern;
  final String marking;
  final String tip;

  /// Words that mark a subject as part of this exam, for planning.
  final List<String> subjects;
}

const examGuide = <ExamInfo>[
  ExamInfo(
    id: 'jee-main',
    name: 'JEE Main',
    summary: 'Run by NTA for admission to NITs, IIITs and other engineering colleges, and the first step to JEE Advanced.',
    pattern: 'Two sessions a year. Paper 1 has Physics, Chemistry and Mathematics: 75 questions in 3 hours, for 300 marks.',
    marking: '+4 for a right answer and −1 for a wrong one, for multiple-choice and numerical questions alike.',
    tip: 'Finish NCERT for Chemistry first, then solve past papers under a 3-hour timer.',
    subjects: ['physics', 'chemistry', 'math', 'maths', 'mathematics'],
  ),
  ExamInfo(
    id: 'jee-advanced',
    name: 'JEE Advanced',
    summary: 'Run by one of the IITs for IIT admission. Only top JEE Main candidates can sit it, with at most two attempts in consecutive years.',
    pattern: 'Two compulsory 3-hour papers on the same day, each covering Physics, Chemistry and Mathematics.',
    marking: 'The pattern and marking change every year, often with partial marks and negative marking in some sections.',
    tip: 'Depth beats breadth here. Solve fewer problems, but understand every step of each one.',
    subjects: ['physics', 'chemistry', 'math', 'maths', 'mathematics'],
  ),
  ExamInfo(
    id: 'neet-ug',
    name: 'NEET-UG',
    summary: 'Run by NTA for MBBS, BDS, AYUSH and other medical courses across India.',
    pattern: 'One pen-and-paper exam: Physics, Chemistry and Biology, 180 questions in 3 hours, for 720 marks.',
    marking: '+4 for a right answer and −1 for a wrong one.',
    tip: 'Biology is half the paper. Read NCERT line by line, and revise its diagrams and examples.',
    subjects: ['physics', 'chemistry', 'biology', 'botany', 'zoology'],
  ),
  ExamInfo(
    id: 'upsc-cse',
    name: 'UPSC CSE',
    summary: 'Run by UPSC for the IAS, IPS, IFS and other central services.',
    pattern: 'Three stages: Prelims (General Studies and CSAT), Mains (nine written papers) and a personality test.',
    marking: 'In Prelims a wrong answer costs a third of the question’s marks, and CSAT only needs 33% to qualify.',
    tip: 'Read a newspaper daily and link it to the syllabus. For Mains, practise writing answers every week.',
    subjects: [
      'history',
      'geography',
      'polity',
      'economy',
      'economics',
      'current affairs',
      'essay',
      'ethics',
      'general studies',
    ],
  ),
  ExamInfo(
    id: 'cat',
    name: 'CAT',
    summary: 'Run by one of the IIMs for MBA admission to the IIMs and many other business schools.',
    pattern: 'Three timed sections — VARC, DILR and Quant — in 2 hours. You can’t switch between sections.',
    marking: '+3 for a right answer and −1 for a wrong multiple-choice answer. Typed answers have no negative marking.',
    tip: 'Take a full mock every week, and spend twice as long reviewing it as you spent taking it.',
    subjects: ['quant', 'verbal', 'varc', 'dilr', 'reasoning', 'english'],
  ),
  ExamInfo(
    id: 'gate',
    name: 'GATE',
    summary: 'Run by IISc and the IITs for M.Tech admission and many PSU jobs. Scores stay valid for three years.',
    pattern: 'One 3-hour paper with 65 questions for 100 marks: 15 marks of General Aptitude and 85 of your subject.',
    marking: 'A wrong multiple-choice answer costs a third of its marks. Multiple-select and numerical questions have no negative marking.',
    tip: 'Past papers repeat ideas often. Solve the last ten years topic by topic.',
    subjects: ['aptitude', 'math', 'maths', 'mathematics'],
  ),
  ExamInfo(
    id: 'cuet-ug',
    name: 'CUET-UG',
    summary: 'Run by NTA for undergraduate admission to central universities and many others.',
    pattern: 'A computer-based test. You choose your subjects, and each test has 50 questions in 60 minutes.',
    marking: '+5 for a right answer and −1 for a wrong one.',
    tip: 'Your Class 12 NCERT books cover most domain subjects. Build speed with timed sets.',
    subjects: ['english', 'general'],
  ),
  ExamInfo(
    id: 'clat',
    name: 'CLAT',
    summary: 'Run by the Consortium of NLUs for law degrees at the National Law Universities.',
    pattern: '120 questions in 2 hours across English, current affairs, legal reasoning, logical reasoning and quantitative techniques.',
    marking: '+1 for a right answer and −0.25 for a wrong one.',
    tip: 'Most questions are built on passages. Read a long editorial daily and time yourself.',
    subjects: ['english', 'legal', 'logical', 'current affairs', 'quant'],
  ),
  ExamInfo(
    id: 'nda',
    name: 'NDA',
    summary: 'Run by UPSC twice a year for the Army, Navy and Air Force wings of the National Defence Academy.',
    pattern: 'Two written papers, Mathematics (300 marks) and the General Ability Test (600 marks), then an SSB interview.',
    marking: 'A wrong answer costs a third of the question’s marks.',
    tip: 'Train your fitness alongside your books. The SSB and medical tests follow the written exam.',
    subjects: ['math', 'maths', 'mathematics', 'english', 'general'],
  ),
  ExamInfo(
    id: 'boards',
    name: 'Board exams',
    summary: 'Your Class 10 or Class 12 board exams, such as CBSE, ICSE or a state board.',
    pattern: 'A written paper for each subject, usually 3 hours long, plus internal assessment and practicals.',
    marking: 'No negative marking. Step-wise marks reward clear, well-set-out working.',
    tip: 'Finish NCERT and the sample papers, then practise writing full answers against the clock.',
  ),
];

/// The exam with [id], or null.
ExamInfo? examById(String? id) {
  for (final exam in examGuide) {
    if (exam.id == id) return exam;
  }
  return null;
}

/// The exam named in [text], if any. [text] should be lowercase.
String? detectExam(String text) {
  bool has(String pattern) => RegExp(pattern).hasMatch(text);
  if (has(r'\bjee\s*(adv|advance|advanced)\b')) return 'jee-advanced';
  if (has(r'\b(jee|iit\s*jee|jee\s*mains?)\b')) return 'jee-main';
  if (has(r'\bneet\b')) return 'neet-ug';
  if (has(r'\b(upsc|ias|ips|civil services?)\b')) return 'upsc-cse';
  if (has(r'\bcat\b')) return 'cat';
  if (has(r'\bgate\b')) return 'gate';
  if (has(r'\bcuet\b')) return 'cuet-ug';
  if (has(r'\bclat\b')) return 'clat';
  if (has(r'\bnda\b')) return 'nda';
  if (has(r'\b(boards?|cbse|icse|class\s*1[02]|1[02]th)\b')) return 'boards';
  return null;
}
