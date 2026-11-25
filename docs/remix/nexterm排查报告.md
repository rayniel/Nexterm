# Nexterm 本地 AI 模型排查与运维报告

- **报告时间**：2026-11-25 14:37 (CST)
- **目标主机**：192.168.2.62（Debian，主机名 `deb13-oci`，用户 `honzon`）
- **排查方式**：SSH 远程登录排查 + 容器内源码分析

---

## 一、环境概览

| 项目 | 值 |
|------|-----|
| Nexterm 部署方式 | Docker（镜像 `nexterm/aio:latest`，版本 **1.2.2-BETA**） |
| 网络模式 | host（宿主机直接监听 6989 端口，HTTP 明文） |
| Web UI 地址 | `http://192.168.2.62:6989` |
| 数据目录 | `/home/honzon/docker-app/nexterm-data` |
| 本地模型服务 | llama.cpp，运行在 **192.168.2.59:8081**（OpenAI 兼容接口） |
| 模型 | `qwen2.5-7b-instruct`（GGUF Q4_K_M），llama.cpp build `b1-b367989` |
| 服务器条目 | `oci`（192.168.2.62，SSH，状态 online） |
| Nexterm 登录账号 | `rayniel` |

---

## 二、问题清单与解决

### 问题 1：本地模型配置「不生效」

**现象**：配置了本地模型，但调用无效。

**根因**（两层）：
1. AI 配置里 **模型名（`model` 字段）为空**（数据库 `nexterm.db` 的 `ai_settings` 表 `model = None`），nexterm 不知道该调用哪个模型。
2. **API Key 为空**。`openai_compatible` 这个 provider 在 nexterm 代码里默认 `requiresApiKey = true`，校验不通过。

**解决**：
- 在 nexterm AI 设置里选定模型 `qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf`；
- API Key 字段随便填一个非空字符串（llama.cpp 不校验 key，填 `none` 即可）。

**状态**：✅ 已解决

---

### 问题 2：「下拉提示无可用模型」 / 找不到「AI助手」按钮

**现象**：模型下拉框显示无可用模型；终端界面找不到「AI助手」按钮。

**根因**：两者本质相同——nexterm 用 `isConfigured` 判断 AI 是否就绪，校验失败时：
- 模型列表接口 `/ai/models` 无法正常返回；
- 前端据此隐藏「AI助手」按钮（`isAIAvailable` 为 false）。

校验失败的直接原因同「问题 1」：`openai_compatible` 强制要求 API Key，而配置里 Key 为空。

**解决**：补填模型名 + API Key 后，`isConfigured` 通过，按钮出现。

**状态**：✅ 已解决

---

### 问题 3：生成命令报错 `No object generated: could not parse the response`

**现象**：「生成命令」功能报错，无法生成命令。

**根因**：
- nexterm 的「生成命令」用 Vercel AI SDK 的 `generateObject`（强制模型返回结构化 JSON）。
- 对 `openai_compatible` provider，nexterm **默认关闭 `supportsStructuredOutputs`**，导致 AI SDK 退回到 `json_object` 模式。
- 而 llama.cpp 在 `json_object` 模式下，模型返回的是**带 markdown 围栏**的 JSON（` ```json {...}``` `），AI SDK 解析失败。

**验证**（实测 llama.cpp）：
| 模式 | 返回 | 结果 |
|------|------|------|
| `json_object` | 带 ```json 围栏 | ❌ 解析失败 |
| `json_schema`（结构化输出） | 纯 JSON | ✅ 正常 |
| tool calling | 正常 | ✅ 正常 |

**解决**：修改容器内 `/app/server/lib/ai/providers.js`，给 `createOpenAICompatible` 增加 `supportsStructuredOutputs: true`，重启容器。

```diff
- const provider = createOpenAICompatible({ name, baseURL: normalizeUrl(baseUrl), apiKey: apiKey || "" });
+ const provider = createOpenAICompatible({ name, baseURL: normalizeUrl(baseUrl), apiKey: apiKey || "", supportsStructuredOutputs: true });
```

- 已备份原文件为 `providers.js.bak`。
- ⚠️ 该补丁打在容器文件系统内，`docker restart` 保留，但**重建容器（`docker rm` + 重新 run / `compose up`）会丢失**，需重新打补丁。

**状态**：✅ 已解决（非持久化，需注意）

---

### 问题 4：「生成命令」输入中文异常（英文正常）

**现象**：生成命令时英文可用，中文输入异常。

**根因**：
- 后端（llama.cpp）中文完全正常（已实测多个中文 prompt 均正确返回）。
- 问题在 **nexterm 前端**：「生成命令」的输入是通过终端键盘捕获（`attachCustomKeyEventHandler`）实现的，其键盘处理**未判断 IME 组合输入状态（`isComposing`）**：
  - 对所有按键 `preventDefault()`；
  - 中文输入法的拼音组合过程被打断，回车确认候选词被误判为「提交生成命令」；
  - 英文不经过输入法，故正常。

**解决（当前方案）**：使用「AI助手」（对话式，输入框为普通文本框，中文正常）代替「生成命令」；或用英文描述。

**状态**：⚠️ 临时规避；根本修复需改前端代码或等官方新版。

---

### 问题 5：终端选择文字后「右键复制」无效

**现象**：面板上选择文字后右键复制无效，怀疑 SSL 证书问题。

**根因**：
- 方向正确但不是「证书有问题」，而是**根本没走 HTTPS**。
- 当前用明文 HTTP + 内网 IP 访问，浏览器的剪贴板 API（`navigator.clipboard.writeText`）只在「安全上下文」（HTTPS 或 localhost）可用，被浏览器禁用，故复制失效。

**解决（两方案）**：
1. **临时**：本机 SSH 隧道转发到 localhost（localhost 是安全上下文，剪贴板立即可用）：
   ```bash
   ssh -L 6989:127.0.0.1:6989 honzon@192.168.2.62
   ```
   然后浏览器访问 `http://localhost:6989`。
2. **正式**：在 .62 上装 nginx + 自签名证书做 HTTPS 反代，访问 `https://192.168.2.62`。**必须配置 WebSocket 转发**（`Upgrade`/`Connection` 头），否则终端和 AI 助手会连不上。

**状态**：⏳ 待实施（已给方案，未动手）

---

### 问题 6：关于「代码补全」功能（咨询）

**结论**：nexterm **没有**「边打字边实时补全」功能。它内置的 AI 能力只有两个（均为主动触发）：
1. **AI 助手**：对话式 agent（读文件、跑命令、改文件，需确认）。
2. **生成命令**：自然语言描述 → 生成命令，接受后填入终端。

阿里云 Workbench 的「智能命令补全」（实时命令/参数补全）是商业产品独有，开源自托管 Web 终端基本没有对标。

**替代方案**：
- 保留浏览器 + shell 层补全：装 **fish**（自带自动建议 + Tab 补全）或 zsh + zsh-autosuggestions。当前 `.62` 是 bash，未装 zsh/fish。
- 换桌面客户端：Warp、Termius（带 AI 补全）。

**状态**：ℹ️ 咨询，未实施

---

## 三、关键配置变更记录

| 变更 | 位置 | 说明 |
|------|------|------|
| 模型名 + API Key 补填 | nexterm Web UI（AI 设置） | 解决 isConfigured 校验失败 |
| `supportsStructuredOutputs: true` | 容器内 `/app/server/lib/ai/providers.js` | 解决生成命令结构化输出失败（非持久化） |
| 原文件备份 | 容器内 `providers.js.bak` | 已备份 |

---

## 四、遗留事项与建议

1. **持久化补丁**（重要）：`providers.js` 补丁在重建容器后会丢失，建议用 volume 覆盖该文件，或记录补丁内容以便重建后重打。
2. **HTTPS 反代**：未实施，建议尽快配置 nginx + 自签名证书，一劳永逸解决复制失效。
3. **中文输入 bug**：属 nexterm 前端缺陷，建议关注官方版本更新；短期用「AI助手」替代。
4. **可选优化**：`.59` 的 llama.cpp 模型名带分片后缀 `-00001-of-00002`，建议启动时加 `--alias qwen2.5-7b-instruct` 使名称更简洁。
5. **代码补全需求**：如确需实时补全体验，可考虑在 `.62` 装 fish。
