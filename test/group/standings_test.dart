import 'package:flutter_test/flutter_test.dart';
import 'package:rocketeye/features/group/group_models.dart';

RoomPlayer p(String id, PlayerState s, {int correct = 0, int score = 0, int ms = 0}) => RoomPlayer(
    uid: id, nickname: id, avatar: '', round: 1, state: s, correct: correct, cells: 16, score: score, elapsedMs: ms);

void main() {
  test('first to clear wins, then by finish time', () {
    final r = standings([
      p('slow', PlayerState.cleared, correct: 16, score: 5000, ms: 12000),
      p('fast', PlayerState.cleared, correct: 16, score: 4000, ms: 8000),
      p('out', PlayerState.out, correct: 9, score: 9000, ms: 5000),
    ]);
    expect(r.map((e) => e.uid), ['fast', 'slow', 'out']);
  });

  test('if nobody clears, highest score wins', () {
    final r = standings([
      p('a', PlayerState.out, correct: 5, score: 700),
      p('b', PlayerState.out, correct: 7, score: 1100),
      p('c', PlayerState.playing, correct: 9),
      p('d', PlayerState.left, correct: 12, score: 3000),
    ]);
    expect(r.map((e) => e.uid), ['b', 'a', 'c', 'd']);
  });

  test('room codes use an unambiguous alphabet', () {
    expect(kRoomAlphabet.contains('O'), isFalse);
    expect(kRoomAlphabet.contains('0'), isFalse);
    expect(kRoomAlphabet.contains('I'), isFalse);
    expect(kRoomAlphabet.contains('1'), isFalse);
    expect(RegExp(r'^[A-HJ-NP-Z2-9]+$').hasMatch(kRoomAlphabet), isTrue);
  });
}
