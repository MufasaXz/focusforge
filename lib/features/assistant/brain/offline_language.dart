/// A small, explicit language layer, not automatic translation. Names, numbers,
/// units and the user's original message are retained by the chat controller.
abstract final class OfflineLanguage {
  static const _phrases = {
    'break it down': 'make it simpler',
    'i still dont get it': 'make it simpler',
    "i still don't get it": 'make it simpler',
    'what do you mean': 'explain that',
    'can you give an example': 'worked example',
    'give me another example': 'another example',
    'walk me through': 'explain',
    "i don't understand": 'explain',
    'i dont understand': 'explain',
    'i dont get': 'explain',
    "i don't get": 'explain',
    'samajh nahi aaya': 'make it simpler',
    'samajh nhi aaya': 'make it simpler',
    'samjh nahi aya': 'make it simpler',
    'समझ नहीं आया': 'make it simpler',
    'आसान शब्दों में': 'in simple words',
    'asaan shabdon mein': 'in simple words',
    'ek aur example': 'another example',
    'एक और उदाहरण': 'another example',
    'aur mushkil sawal': 'harder',
    'अगला सवाल': 'next question',
    'jawab batao': 'show answer',
    'जवाब बताओ': 'show answer',
    'mujhe nahi pata': 'i dont know',
    'मुझे नहीं पता': 'i dont know',
    'aaj kya padhna chahiye': 'what should i study today',
    'आज क्या पढ़ूं': 'what should i study today',
    'आज क्या पढूं': 'what should i study today',
    'padhai shuru karo': 'start a block',
    'पढ़ाई शुरू करो': 'start a block',
    'टाइमर शुरू करो': 'start timer',
    'shuru mat karo': 'do not start',
    'शुरू मत करो': 'do not start',
    'yaad mat dilana': 'do not remind me',
    'yaad dilana': 'remind me',
    'याद दिलाना': 'remind me',
    'mera progress': 'my progress',
    'meri progress': 'my progress',
    'मेरी प्रगति': 'my progress',
    'कितना पढ़ा': 'my report',
    'time table': 'timetable',
    'मेरा टाइमटेबल': 'my timetable',
    'half an hour': '30 minutes',
    'aadha ghanta': '30 minutes',
    'आधा घंटा': '30 minutes',
    'mere paas': 'i have',
    'मेरे पास': 'i have',
    'sirf': 'only',
    'सिर्फ': 'only',
    'मिनट': 'minutes',
    'ghante': 'hours',
    'ghanta': 'hour',
    'घंटे': 'hours',
    'घंटा': 'hour',
    'samjhao': 'explain',
    'samjha do': 'explain',
    'समझाओ': 'explain',
    'समझा दो': 'explain',
    'exaplain': 'explain',
    'explane': 'explain',
    'explan': 'explain',
    'revison': 'revision',
    'timetabel': 'timetable',
    'motivatoin': 'motivation',
    'concentraton': 'concentration',
    'धन्यवाद': 'thank you',
    'नमस्ते': 'hello',
  };

  static String understand(String input) {
    if (input.length > 2000) return input;
    var result = input.replaceAll(RegExp('[’‘]'), "'");
    const digits = ['०१२३४५६७८९', '٠١٢٣٤٥٦٧٨٩'];
    for (final alphabet in digits) {
      for (var i = 0; i < 10; i++) {
        result = result.replaceAll(alphabet[i], '$i');
      }
    }
    final phrases = _phrases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final phrase in phrases) {
      final pattern = RegExp(
        '(^|[\\s,.!?])${RegExp.escape(phrase)}(?=\$|[\\s,.!?])',
        caseSensitive: false,
      );
      result = result.replaceAllMapped(
        pattern,
        (m) => '${m[1]}${_phrases[phrase]}',
      );
    }
    return result;
  }

  /// A denied, hypothetical or explanatory action must not start a timer or
  /// remove reminders. A subsequent explicit command remains available.
  static String? actionGuard(String input, {bool allowsReminderDate = false}) {
    final text = understand(input).toLowerCase().replaceAll("'", '');
    final command = RegExp(
      r'\b(start|begin|lock|block|remind|reminder|reminders|timetable|schedule|goal|delete|remove|stop|turn off)\b',
    );
    if (!command.hasMatch(text)) return null;
    if (RegExp(r'\b(dont|do not|never|not yet|mat|nahi karna|nhi karna)\b')
            .hasMatch(text) ||
        text.contains('मत ') ||
        text.contains('नहीं करना')) {
      return 'declined';
    }
    final hypothetical = allowsReminderDate
        ? text.replaceAll(RegExp(r'\b\d{1,3} (?:din|days?) later\b'), '')
        : text;
    if (RegExp(
          r'\b(how do i|how to|how can i|how does|what happens if|what if|why does|why did|can you explain|explain how)\b',
        ).hasMatch(text) ||
        RegExp(r'\b(if|unless|maybe|later)\b').hasMatch(hypothetical)) {
      return 'explain';
    }
    return null;
  }
}
