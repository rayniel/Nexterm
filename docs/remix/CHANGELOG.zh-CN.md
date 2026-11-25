# Remix 分支修复记录

`main` 与上游 `gnmyt/Nexterm` 保持一致，所有自定义修改只在 `remix` 分支。
原始问题见同目录的 [nexterm排查报告.md](./nexterm排查报告.md)。

## 已提交的修复

| 问题 | 修复 | 文件 |
|---|---|---|
| OpenAI 兼容（llama.cpp 等本地模型）强制要求 API Key、模型列表为空 | `openai_compatible` 不再要求 API Key | `server/lib/ai/providers.js` |
| 「生成命令」报 `No object generated: could not parse the response` | 对 `openai_compatible` 启用 `supportsStructuredOutputs` | `server/lib/ai/providers.js` |
| 「生成命令」输入框中文输入法无法输入 | 输入法组合期间（`isComposing` / keyCode 229）不拦截按键；`onData` 在建议激活时把提交的文本追加到查询 | `client/.../renderer/XtermRenderer.jsx` |
| 本地构建镜像 | 新增 `build-local.sh`（`git pull` 后运行即可在本地构建镜像） | `build-local.sh` |
| 国内构建极慢 | Dockerfile 支持 `APK_MIRROR` / `NPM_REGISTRY` 构建参数，并改写 `yarn.lock` 中的 registry 地址 | `Dockerfile*`、`build-local.sh` |
| engine 镜像缺少 `nexterm-webview` 等 | 默认 `ENGINE_IMAGE` 改为 `nexterm/engine:development`（与 main 匹配） | `build-local.sh` |
| 容器启动即崩溃（SIGILL，退出码 132，无日志） | `@napi-rs/canvas`（Skia）需要 AVX，QEMU 默认 vCPU 没有；改为延迟加载，仅在远程桌面截图时才加载 | `server/lib/agentTools/GuacDisplay.js` |
| 中文文档 | 新增 `README.remix.zh-CN.md` | `README.remix.zh-CN.md` |

## 未改动 / 已知限制

- 右键复制：上游已有 `execCommand` 回退；剪贴板读取/粘贴在纯 HTTP 下仍受浏览器安全上下文限制，需 HTTPS 或 localhost。
- 实时补全：上游无此功能，未实现。
- 虚拟机建议把 CPU 类型设为 `host`，否则远程桌面截图功能（需要 AVX）仍会崩溃。
