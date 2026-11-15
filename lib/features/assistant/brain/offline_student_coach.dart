import 'assistant_models.dart';
import 'offline_text.dart';
import 'study_snapshot.dart';

/// Authored Hindi/Hinglish coaching for common student requests. Topic lessons
/// retain their authored language; this does not pretend to translate them.
abstract final class OfflineStudentCoach {
  static String? kind(String input) {
    final text = OfflineText.normalize(input);
    if (OfflineText.any(text, const [
      'yaad nahi rehta',
      'yaad nhi rehta',
      'bhool jata',
      'bhul jata',
      'याद नहीं रहता',
      'भूल जाता',
      'याद कैसे रखूं',
    ])) {
      return 'recall';
    }
    if (OfflineText.any(text, const [
      'mann nahi lag',
      'man nahi lag',
      'padhne ka mann nahi',
      'padhne ka man nahi',
      'padhai nahi ho rahi',
      'padhai nhi ho rahi',
      'पढ़ाई में मन नहीं',
      'पढ़ने का मन नहीं',
      'ध्यान नहीं लग',
      'ध्यान कैसे लगाऊं',
    ])) {
      return 'focus';
    }
    if (OfflineText.any(text, const [
      'kal exam hai',
      'kal paper hai',
      'कल परीक्षा है',
      'कल एग्जाम है',
    ])) {
      return 'exam';
    }
    if (OfflineText.any(text, const [
      'aaj kitni padhai',
      'आज कितना पढ़ा',
      'आज कितनी पढ़ाई',
    ])) {
      return 'progress';
    }
    if (OfflineText.any(text, const [
      'backlog kaise',
      'backlog bahut',
      'bahut backlog',
      'बैकलॉग कैसे',
      'बहुत बैकलॉग',
    ])) {
      return 'backlog';
    }
    return null;
  }

  static AssistantReply? reply(String input, StudySnapshot s) {
    final intent = kind(input);
    if (intent == null) return null;
    final hindi = RegExp(r'[\u0900-\u097f]').hasMatch(input);
    final needs = [...s.subjects]
      ..sort(
        (a, b) =>
            (b.weekTarget - b.thisWeek).compareTo(a.weekTarget - a.thisWeek),
      );
    final topic = needs.isEmpty
        ? (hindi ? 'एक छोटा विषय' : 'ek chhota topic')
        : needs.first.name;
    final left = (s.goalMinutes - s.todayMinutes).clamp(0, 1440);
    final answer = switch ((intent, hindi)) {
      ('recall', true) =>
        '$topic पढ़ने के बाद नोट्स बंद करें। बिना देखे तीन बातें लिखें, फिर छूटी बातें जाँचें। कल, तीन दिन बाद और एक हफ्ते बाद दोहराएँ। सिर्फ दोबारा पढ़ने से बेहतर है खुद से सवाल पूछना। किस टॉपिक में सबसे ज्यादा भूलते हैं?',
      ('recall', false) =>
        '$topic padhne ke baad notes band karo. Bina dekhe 3 points likho, phir jo chhoot gaya use check karo. Kal, 3 din baad aur ek hafte baad recall karo. Sirf rereading se behtar hai khud se sawal poochna. Kis topic mein sabse zyada bhoolte ho?',
      ('focus', true) =>
        'अभी पूरा दिन ठीक करने की जरूरत नहीं है। $topic का सिर्फ एक छोटा हिस्सा चुनें। फोन अलग रखकर 5 मिनट पढ़ें, फिर तय करें कि आगे बढ़ना है या थोड़ा आराम करना है। आज आपने ${s.todayMinutes} फोकस मिनट दर्ज किए हैं। ज्यादा दिक्कत थकान से है या ध्यान भटकने से?',
      ('focus', false) =>
        'Abhi poora din fix karne ki zaroorat nahi. $topic ka ek chhota hissa chuno. Phone alag rakhkar 5 minute padho, phir decide karo aage badhna hai ya break lena hai. Aaj tumne ${s.todayMinutes} focus minutes log kiye hain. Zyada dikkat thakaan se hai ya distractions se?',
      ('exam', true) =>
        'कल की परीक्षा के लिए नया बड़ा अध्याय शुरू करने के बजाय परिचित टॉपिक और अपनी गलतियाँ दोहराएँ। $topic से 20 मिनट की रिवीजन करें, 5 मिनट आराम करें, फिर एक छोटा अभ्यास सेट करें। रात भर जागने से बचें और जरूरी सामान तैयार रखें। किस विषय की परीक्षा है?',
      ('exam', false) =>
        'Kal ke paper ke liye naya bada chapter shuru karne ke bajaye familiar topics aur mistakes revise karo. $topic se 20 minute revision, 5 minute break, phir ek short practice set. Raat bhar jagne se bacho aur exam ka samaan ready rakho. Kis subject ka paper hai?',
      ('progress', true) =>
        'आज ${s.todayMinutes} मिनट और इस हफ्ते ${s.weekMinutes} मिनट दर्ज हैं। आपकी स्ट्रीक ${s.streak} दिन है। ${s.goalMinutes <= 0
            ? 'आज का लक्ष्य तय नहीं है।'
            : left == 0
            ? 'आज का लक्ष्य पूरा है।'
            : 'आज के लक्ष्य में $left मिनट बाकी हैं।'} ये इस डिवाइस के दर्ज अध्ययन आँकड़े हैं।',
      ('progress', false) =>
        'Aaj ${s.todayMinutes} minutes aur is hafte ${s.weekMinutes} minutes log hue hain. Streak ${s.streak} din ki hai. ${s.goalMinutes <= 0
            ? 'Aaj ka goal set nahi hai.'
            : left == 0
            ? 'Aaj ka goal poora hai.'
            : 'Aaj ke goal mein $left minutes baaki hain.'} Ye is device par logged study ke numbers hain.',
      ('backlog', true) =>
        'पहले बचे अध्यायों को तीन हिस्सों में बाँटें: जरूरी, अभ्यास चाहिए, और बाद में। आज $topic का एक जरूरी हिस्सा चुनें। 25 मिनट समझें, 5 मिनट आराम, फिर 10 मिनट बिना नोट्स सवाल हल करें। हर अधूरा अध्याय आज खत्म करना जरूरी नहीं। कितने अध्याय और कितने दिन बाकी हैं?',
      _ =>
        'Bache chapters ko teen groups mein rakho: zaroori, practice chahiye, aur baad mein. Aaj $topic ka ek important hissa chuno: 25 minute samjho, 5 minute break, phir 10 minute bina notes questions karo. Sab kuch aaj khatam karna zaroori nahi. Kitne chapters aur kitne din baaki hain?',
    };
    return AssistantReply([Say(Copy.raw(answer))]);
  }
}
