import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo_app/models/training.dart';
import 'package:todo_app/services/ai_service.dart';
import 'package:todo_app/services/energy_service.dart';
import 'package:todo_app/services/food_estimation_service.dart';

void main() {
  WorkoutSet set(
          {int reps = 10,
          int grams = 20000,
          String name = '深蹲',
          int? seconds}) =>
      WorkoutSet.create(
          workoutId: 0,
          exerciseName: name,
          reps: reps,
          weightGrams: grams,
          durationSeconds: seconds);
  test(
      'training estimate accounts for recorded sets, body weight and load class',
      () {
    final light = EnergyService.estimateTraining(weightKg: 70, sets: [set()])!;
    final heavy = EnergyService.estimateTraining(
        weightKg: 70, sets: [set(grams: 60000)])!;
    final more =
        EnergyService.estimateTraining(weightKg: 70, sets: [set(), set()])!;
    expect(heavy.calories, greaterThan(light.calories));
    expect(more.calories, greaterThan(light.calories));
    expect(light.inferredDuration, isTrue);
    expect(EnergyService.estimateTraining(weightKg: double.nan, sets: [set()]),
        isNull);
    expect(EnergyService.estimateTraining(weightKg: 70, sets: []), isNull);
  });
  test('cardio uses net MET energy and seconds are not treated as minutes', () {
    final result = EnergyService.estimateTraining(
        weightKg: 70,
        sets: [set(name: '跑步', seconds: 1800)],
        durationMinutes: 30)!;
    expect(result.calories, closeTo((8 - 1) * 3.5 * 70 / 200 * 30, 1));
    expect(result.minutes, 30);
    expect(result.inferredDuration, isFalse);
  });
  test(
      'advice never treats missing food or unfinished day as a calorie deficit',
      () {
    expect(
        EnergyService.advice(
            intake: 0, missingEntries: 0, expenditure: 2000, isToday: true),
        contains('尚未记录'));
    expect(
        EnergyService.advice(
            intake: 100, missingEntries: 1, expenditure: 2000, isToday: false),
        contains('先补全'));
    expect(
        EnergyService.advice(
            intake: 500, missingEntries: 0, expenditure: 2000, isToday: true),
        contains('今天尚未结束'));
  });
  test('offline single-food lookup honours explicit grams and portions', () {
    expect(FoodEstimationService.local('米饭 150g')!.calories, 174);
    expect(FoodEstimationService.local('鸡蛋 2个')!.calories, 144);
    expect(FoodEstimationService.local('番茄炒蛋'), isNull);
    expect(FoodEstimationService.local('香蕉 0g'), isNull);
    expect(FoodEstimationService.local('米饭 100000g'), isNull);
  });
  test('AI estimate rejects missing food, invalid calories and non-JSON', () {
    for (final data in [
      {'food': '', 'calories': 0},
      {'food': '餐食'},
      {'food': '餐食', 'calories': -1},
      {'food': '餐食', 'calories': 10001},
    ]) {
      expect(() => FoodEstimate.parse(jsonEncode(data)), throwsFormatException);
    }
    expect(() => FoodEstimate.parse('not JSON'), throwsFormatException);
    final parsed =
        FoodEstimate.parse('```json\n{"food":"米饭 150g","calories":174}\n```');
    expect(parsed.calories, 174);
    expect(parsed.explanation, contains('估计值'));
  });
  test(
      'photo sends multimodal content with explicit vision model and no app context',
      () async {
    Map? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map;
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'food': '米饭 150g',
                    'calories': 174,
                    'explanation': '按一小碗估计'
                  })
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    addTearDown(client.close);
    final estimator = FoodEstimationService(ai: AiService.forTest(client));
    final result = await estimator.byPhoto(
        Uint8List.fromList([255, 216, 255]),
        'image/jpeg',
        const AiConfig(
            enabled: true,
            apiKey: 'test',
            model: 'text-only',
            visionModel: 'vision-model'));
    expect(result.calories, 174);
    expect(body!['model'], 'vision-model');
    final content = (body!['messages'] as List)[1]['content'] as List;
    expect(content[0]['type'], 'text');
    expect(
        content[1]['image_url']['url'], startsWith('data:image/jpeg;base64,'));
    expect(body.toString(), isNot(contains('备忘录')));
  });
  test('disabled AI and invalid photo do not make a request', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    final estimator = FoodEstimationService(ai: AiService.forTest(client));
    expect((await estimator.byName('米饭 150g', const AiConfig())).calories, 174);
    await expectLater(
        estimator.byPhoto(Uint8List(1), 'image/jpeg', const AiConfig()),
        throwsException);
    await expectLater(
        estimator.byPhoto(Uint8List(6 * 1024 * 1024), 'image/jpeg',
            const AiConfig(enabled: true, apiKey: 'test')),
        throwsException);
    expect(requests, 0);
  });
}
