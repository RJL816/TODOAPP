# AI 助手兼容与预设核验

核验日期：2026-10-12。预设仅采用各家官方文档当前列出的型号；这不是账户可用性或收费调用验证。不同平台、地域和账户的模型权限与额度仍由服务商决定。

| 服务商 | 当前预设模型 ID | Chat Completions Base URL | 官方依据 |
| --- | --- | --- | --- |
| 智谱 | `glm-5.3-flash`、`glm-5.3-flashx`、`glm-5.3` | `https://open.bigmodel.cn/api/paas/v4` | [GLM-5.3](https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3)、[GLM-5.3-Flash/FlashX](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5.3-flash) |
| DeepSeek | `deepseek-flash`、`deepseek-v4-pro` | `https://api.deepseek.com/v1` | [首次调用](https://api-docs.deepseek.com/)、[Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/) |
| Kimi | `kimi-k3`、`kimi-k2.7-code`、`kimi-k2.6` | `https://api.moonshot.cn/v1` | [官方快速开始](https://platform.kimi.com/docs/get-api-key) |
| 通义 | `qwen3.8-flash`、`qwen3.7-plus`、`qwen3.8-max` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | [当前文本模型](https://help.aliyun.com/zh/model-studio/text-generation-model)、[Chat API 与地域地址](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions) |

阿里云当前推荐使用含业务空间 ID 的地域专属域名；官方文档明确原 `dashscope.aliyuncs.com` 仍可使用，所以预设保留可直接填写的北京地域通用地址。用户填写的专属域名、国际地域地址和第三方网关不会被预设覆盖。

移除原预设中的旧 GLM、DeepSeek 旧别名、Kimi 预览快照、Moonshot v1 和旧通义型号。移除表示它们不在本次核验的当前预设中，不能据此断言所有旧型号都已停服。保留用户既有配置和手动输入，包括用户确认可用的 `glm-4-flash`；没有批量改写用户保存的模型名。

## 已确认的代码缺陷与修复

- 原地址、Key、模型输入框只在 `onSubmitted` 时保存；点击测试可能使用旧值。保存 Key 按钮也读取旧配置。现由持久的输入控制器维护草稿，输入后保存，测试前立即保存全部当前值。
- 原输入控制器在每次设置重建时创建，切换开关/预设可丢失未提交的输入。现保留控制器并在销毁时释放；串行写入避免旧草稿覆盖新草稿。
- 原连接测试额外施加 20 秒超时，而服务层 60 秒也不利于思考模型。现统一服务层 180 秒等待，禁用测试按钮防止重复请求，并持续显示结果。
- 原请求强制所有模型使用 `temperature: 0.7`。现省略采样参数，采用模型默认值。
- 原 URL 一律追加 `/chat/completions`，填写完整端点时会重复追加。现接受 Base URL 和完整 Chat Completions 端点，保留查询参数，并拒绝误填的 Responses/Messages 端点。
- 原 401/403/429 提示覆盖服务商错误详情。现保留 HTTP 状态、业务错误码和信息，隐藏回显的 Key，并识别非 JSON、文本块和没有最终回答的长度限制情况。

## 思考模型

仅对已核验的官方域名和型号设置轻量推理 `reasoning_effort: low`，第三方网关保持最小兼容请求：

- GLM-5.3/Flash/FlashX：[官方参数](https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3)。始终开启思考，不能传 `thinking.type: disabled`。
- DeepSeek Flash/Pro：[思考模式](https://api-docs.deepseek.com/guides/thinking_mode/)。默认开启思考、默认力度 high，支持 low/high/max。
- Kimi K3：[快速开始](https://platform.kimi.com/docs/get-api-key)。支持 low/high/max，默认 max。
- Qwen3.8 Max/Flash：[Chat API 参数](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions)。支持 low/medium/xhigh，不同时设置 thinking_budget。

不把 `reasoning_content` 当作最终回答；仍通过 `choices[].message.content` 读取结果。助手暂时使用非流式 Chat Completions、每次请求独立，不调用 Responses 或 Anthropic Messages API。

## 验证范围

自动化测试使用 MockClient，不消耗真实 API 额度，覆盖当前预设的请求体、地址规范化、错误详情、超时、输入后直接测试、保存 Key、第三方网关保护。模型名的真实性来自上述官方文档，真实账户调用需在应用中点击“测试连接”确认。
