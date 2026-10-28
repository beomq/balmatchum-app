/// Korean particles chosen by a word's last sound, shared by the onboarding,
/// home and photo copy.
library;

/// The final consonant of [value]'s last sound as a jongseong index: 0 for
/// none, 8 for ㄹ. Digits are read in Korean; other characters count as
/// ending in a vowel.
int batchim(String value) {
  final last = value.codeUnitAt(value.length - 1);
  if (last >= 0xAC00 && last <= 0xD7A3) return (last - 0xAC00) % 28;
  // 영 일 삼 육 칠 팔 end in ㅇ ㄹ ㅁ ㄱ ㄹ ㄹ; 이 사 오 구 in a vowel.
  return const {
        '0': 21,
        '1': 8,
        '3': 16,
        '6': 1,
        '7': 8,
        '8': 8,
      }[String.fromCharCode(last)] ??
      0;
}

/// `{name}와` or `{name}과` by the name's last sound.
String withWa(String name) {
  final value = name.trimRight();
  if (value.isEmpty) return name;
  return '$value${batchim(value) == 0 ? '와' : '과'}';
}

/// `{name}를` or `{name}을` by the name's last sound.
String withEul(String name) {
  final value = name.trimRight();
  if (value.isEmpty) return name;
  return '$value${batchim(value) == 0 ? '를' : '을'}';
}

/// `{value}야` after a vowel, `{value}이야` after a consonant.
String withIya(String value) => '$value${batchim(value) == 0 ? '야' : '이야'}';

/// `{value}로` after a vowel or ㄹ, `{value}으로` after another consonant.
String withRo(String value) =>
    '$value${switch (batchim(value)) {
      0 || 8 => '로',
      _ => '으로',
    }}';
