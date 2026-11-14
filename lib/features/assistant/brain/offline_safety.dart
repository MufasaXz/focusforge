import 'offline_text.dart';

/// Fixed, age-appropriate replies, checked before command execution or cloud
/// routing. This is a conservative local guard, not a claim to detect every
/// harmful request in every language.
abstract final class OfflineSafety {
  static String? reply(String input) {
    final text = OfflineText.normalize(input);
    if (OfflineText.any(text, const [
      'kill myself',
      'hurt myself',
      'cut myself',
      'cutting myself',
      'end it all',
      'harm myself',
      'end my life',
      'want to die',
      'wish i was dead',
      'suicide',
      'suicidal',
      'self harm',
      'jeena nahi',
      'marna chahta',
      'marna chahti',
      'khud ko mar',
      'आत्महत्या',
      'खुद को नुकसान',
      'जीना नहीं',
    ])) {
      return 'Your safety matters more than studying. Please tell a trusted '
          'adult or someone you trust now, and stay near them. If you might '
          'hurt yourself or are in immediate danger, contact your local '
          'emergency services now. I am a study assistant and cannot provide '
          'emergency care.';
    }
    if (OfflineText.any(text, const [
      'make a bomb',
      'build a bomb',
      'make explosives',
      'make a weapon',
      'hurt someone',
      'kill someone',
      'poison someone',
      'porn',
      'pornography',
      'explicit sexual',
      'nude pictures',
      'sexual roleplay',
      'steal passwords',
      'steal credentials',
      'hack an account',
      'hack someones account',
      'bypass parental controls',
    ])) {
      return 'I can help with safe learning and study skills. Try a subject '
          'explanation, a practice question, or a short study plan.';
    }
    if (OfflineText.any(text, const [
      'ignore all instructions',
      'ignore previous instructions',
      'ignore your instructions',
      'reveal your system prompt',
      'show your system prompt',
      'developer mode',
      'jailbreak',
      'reveal api key',
      'show api key',
      'print secrets',
    ])) {
      return 'I can explain study topics and help you practise. I cannot '
          'reveal private information or change my study-only role.';
    }
    if (OfflineText.any(text, const [
      'cheat in exam',
      'cheat on exam',
      'cheat on my exam',
      'answers to my live exam',
      'take my exam for me',
      'write my assignment for submission',
      'plagiarize',
    ])) {
      return 'I can help you learn the method, practise a similar problem, '
          'or outline your own answer. For assessed work, follow your '
          'school’s rules and write the final work yourself.';
    }
    if (OfflineText.any(text, const [
      'stay awake all night',
      'skip sleep',
      'study without sleeping',
      'study 24 hours',
      'study 20 hours',
      'study 18 hours',
      'which pills',
      'which medicine',
      'diagnose me',
    ])) {
      return 'Protect your sleep, meals, and breaks. Choose a manageable '
          'revision block instead of an all-night catch-up. I cannot advise '
          'on medication or diagnose health concerns; ask a qualified '
          'professional, with a trusted adult if you are a child.';
    }
    return null;
  }
}
