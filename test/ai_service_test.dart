import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo_app/services/ai_service.dart';

http.Response answer(Object content) => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'content': content},
          'finish_reason': 'stop'
        }
      ]
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Future<String> ask(AiService service,
        {AiConfig config = const AiConfig(apiKey: 'test-key')}) =>
    service.chat(config: config, system: '助手', user: '你好');

void main() {
  for (final (input, expected) in [
    (' https://example.com/v1/ ', 'https://example.com/v1/chat/completions'),
    ('https://api.deepseek.com', 'https://api.deepseek.com/chat/completions'),
    (
      'https://example.com/v1/chat/completions/',
      'https://example.com/v1/chat/completions'
    ),
    (
      'https://example.com/custom?version=1',
      'https://example.com/custom/chat/completions?version=1'
    ),
  ]) {
    test('normalizes endpoint $input', () {
      expect(AiService.chatEndpoint(input).toString(), expected);
    });
  }
  test('rejects invalid URLs and other API protocols', () {
    for (final input in [
      '',
      'api.example.com',
      'ftp://example.com',
      'https://example.com/v1/messages',
      'https://example.com/v1/responses',
    ]) {
      expect(() => AiService.chatEndpoint(input), throwsException);
    }
  });

  for (final (model, address, effort) in [
    ('glm-4-flash', AiConfig.defaultBaseUrl, null),
    ('glm-5.3', AiConfig.defaultBaseUrl, 'low'),
    ('glm-5.3-flash', AiConfig.defaultBaseUrl, 'low'),
    ('glm-5.3-flashx', AiConfig.defaultBaseUrl, 'low'),
    ('deepseek-flash', 'https://api.deepseek.com/v1', 'low'),
    ('deepseek-v4-pro', 'https://api.deepseek.com', 'low'),
    ('kimi-k3', 'https://api.moonshot.cn/v1', 'low'),
    ('kimi-k2.7-code', 'https://api.moonshot.cn/v1', null),
    ('kimi-k2.6', 'https://api.moonshot.cn/v1', null),
    ('qwen3.8-flash', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'low'),
    ('qwen3.8-max', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'low'),
    ('qwen3.7-plus', 'https://dashscope.aliyuncs.com/compatible-mode/v1', null),
    ('qwen3.8-flash',
        'https://workspace.cn-beijing.maas.aliyuncs.com/compatible-mode/v1', 'low'),
    ('glm-5.3', 'https://proxy.example/v1', null),
  ]) {
    test('compatible request for $model at $address', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['model'], model);
        expect(body['temperature'], isNull);
        expect(body['stream'], isFalse);
        expect(body['reasoning_effort'], effort);
        expect(body['thinking'], isNull);
        expect(request.headers['authorization'], 'Bearer test-key');
        expect((body['messages'] as List).first['content'], '助手');
        return answer('连接成功');
      });
      addTearDown(client.close);
      expect(
          await ask(AiService.forTest(client),
              config: AiConfig(
                  baseUrl: address, apiKey: ' test-key ', model: ' $model ')),
          '连接成功');
    });
  }

  test('reads text blocks without showing reasoning as the final answer',
      () async {
    final client = MockClient((_) async => answer([
          {'type': 'reasoning', 'text': '私有推理'},
          {'type': 'text', 'text': '第一段'},
          {'type': 'output_text', 'text': '第二段'},
        ]));
    addTearDown(client.close);
    expect(await ask(AiService.forTest(client)), '第一段\n第二段');
  });

  for (final status in [401, 403, 404, 429]) {
    test('preserves provider error details for HTTP $status', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': {'code': 'model_access_denied', 'message': '请开通模型权限'}
          }),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      addTearDown(client.close);
      await expectLater(
          ask(AiService.forTest(client)),
          throwsA(predicate((error) =>
              error.toString().contains('HTTP $status') &&
              error.toString().contains('model_access_denied') &&
              error.toString().contains('请开通模型权限'))));
    });
  }
  test('reads top-level code/message errors and redacts the key', () async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({'code': 'InvalidApiKey', 'message': 'invalid test-key'}),
        401));
    addTearDown(client.close);
    await expectLater(
        ask(AiService.forTest(client)),
        throwsA(predicate((error) =>
            error.toString().contains('InvalidApiKey') &&
            !error.toString().contains('test-key'))));
  });
  test('reports invalid JSON rather than a cast exception', () async {
    final client =
        MockClient((_) async => http.Response('<html>error</html>', 200));
    addTearDown(client.close);
    await expectLater(ask(AiService.forTest(client)),
        throwsA(predicate((error) => error.toString().contains('有效 JSON'))));
  });
  test('reports reasoning-only length exhaustion', () async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': null, 'reasoning_content': 'thinking'},
              'finish_reason': 'length',
            }
          ]
        }),
        200));
    addTearDown(client.close);
    await expectLater(ask(AiService.forTest(client)),
        throwsA(predicate((error) => error.toString().contains('输出长度限制'))));
  });
  test('uses the transport timeout for slow models', () async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    addTearDown(client.close);
    final request = ask(AiService.forTest(client,
        requestTimeout: const Duration(milliseconds: 10)));
    await expectLater(request,
        throwsA(predicate((error) => error.toString().contains('等待模型回复超时'))));
    pending.complete(answer('迟到的回答'));
  });
}
