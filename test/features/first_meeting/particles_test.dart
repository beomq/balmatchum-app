import 'package:balmatchum_app/features/first_meeting/particles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('particles follow the last sound, digits read in Korean', () {
    expect(withWa('코코'), '코코와');
    expect(withWa('초롱'), '초롱과');
    expect(withEul('코코'), '코코를');
    expect(withEul('초롱'), '초롱을');
    expect(withEul('몽글'), '몽글을');
    // 2 is 이 (no final consonant), 3 is 삼.
    expect(withEul('콩2'), '콩2를');
    expect(withEul('콩3'), '콩3을');
    expect(withEul('Max'), 'Max를');
    expect(withRo('몽글'), '몽글로');
    expect(withRo('초롱'), '초롱으로');
    expect(withIya('초롱'), '초롱이야');
    // Blank names pass through untouched instead of failing.
    expect(withEul(''), '');
    expect(withWa('  '), '  ');
  });
}
