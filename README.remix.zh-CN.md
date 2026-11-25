# Nexterm Remix 分支说明

本分支（`remix`）基于上游 [gnmyt/Nexterm](https://github.com/gnmyt/Nexterm)，`main` 与上游保持一致，所有个人修改只放在 `remix`。

## 与上游的差异

| 修改 | 文件 | 说明 |
|------|------|------|
| 本地镜像构建脚本 | `build-local.sh` | 一条命令构建本地 all-in-one 镜像 |
| `openai_compatible` 不再强制 API Key | `server/lib/ai/providers.js` | llama.cpp / vLLM 等本地模型无需填假 Key |
| `openai_compatible` 启用结构化输出 | `server/lib/ai/providers.js` | 修复「生成命令」报 `No object generated: could not parse the response` |
| 「生成命令」支持中文输入法 | `client/.../XtermRenderer.jsx` | 处理 IME 组合输入，拼音不再被打断 |

## 本地构建镜像

前置：已安装 Docker。

```bash
git clone -b remix https://github.com/rayniel/Nexterm.git
cd Nexterm
./build-local.sh            # 默认镜像名 nexterm-remix:latest
./build-local.sh my/nexterm:dev   # 自定义镜像名
```

构建流程：拉取官方 engine 镜像 → 本地构建 server 镜像 → 合成 all-in-one 镜像。

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ENGINE_IMAGE` | `nexterm/engine:latest` | 复用的预构建 engine 镜像 |
| `BUILD_ENGINE` | `0` | 设为 `1` 时从源码构建 engine（见下） |
| `PLATFORM` | 本机平台 | 如 `linux/amd64`、`linux/arm64` |

### BUILD_ENGINE=1 怎么设置

engine 包含 Guacamole（RDP/VNC）等 C/Rust 组件，从源码构建非常慢（可能数十分钟），通常**不需要**。只有修改了 engine / guacamole 源码，或官方 engine 镜像与你的平台不匹配时才使用。

环境变量写在命令前面即可（不是脚本参数）：

```bash
# Linux / macOS / WSL / Git Bash
BUILD_ENGINE=1 ./build-local.sh

# 同时指定镜像名和平台
BUILD_ENGINE=1 PLATFORM=linux/amd64 ./build-local.sh my/nexterm:dev

# 或先 export
export BUILD_ENGINE=1
./build-local.sh
```

使用自己的 engine 镜像（不从源码构建）：

```bash
ENGINE_IMAGE=myrepo/engine:custom ./build-local.sh
```

### 国内网络加速（换源）

构建慢或卡在 `apk add` / `yarn install` 时，可指定镜像源（作用于 Dockerfile 所有阶段）：

```bash
APK_MIRROR=https://mirrors.aliyun.com NPM_REGISTRY=https://registry.npmmirror.com ./build-local.sh
```n
`NPM_REGISTRY` 会同时改写 `yarn.lock` 里写死的 `registry.yarnpkg.com` 下载地址（仅构建时，不改仓库文件）。

注意：加 `sudo` 时环境变量要写在 sudo 后面：`sudo APK_MIRROR=... NPM_REGISTRY=... ./build-local.sh`。
从源码构建 engine 时还会从 `archive.mesa3d.org` 和 GitHub 下载源码包，无法换源，必要时给 Docker 配代理。

## 运行

```bash
docker run -d --name nexterm --network host \
  -v nexterm-data:/app/data \
  nexterm-remix:latest
```

访问 `http://<主机IP>:6989`。

或使用 docker compose：

```yaml
services:
  nexterm:
    image: nexterm-remix:latest
    container_name: nexterm
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./nexterm-data:/app/data
```

更新：在 `remix` 分支 `git pull` 后重新运行 `./build-local.sh`，再 `docker rm -f nexterm` 并重新启动（数据在卷中不会丢失）。

## 本地 AI 模型配置（llama.cpp 等）

1. 设置 → AI，提供商选 **OpenAI Compatible**。
2. Base URL 填 `http://<IP>:8081/v1`，**API Key 可留空**。
3. 选择模型名。建议 llama.cpp 启动时加 `--alias qwen2.5-7b-instruct`，避免分片后缀过长。
4. 配置完成后终端会出现「AI 助手」按钮。

## 已知问题

- **HTTP 下复制/粘贴受限**：浏览器剪贴板 API 只在 HTTPS 或 `localhost` 可用。建议用 nginx + 证书反代（必须转发 WebSocket 的 `Upgrade` / `Connection` 头），或通过 SSH 隧道访问：`ssh -L 6989:127.0.0.1:6989 user@host` 后打开 `http://localhost:6989`。
- Nexterm 没有实时命令补全功能，可在服务器上安装 fish 或 zsh-autosuggestions 替代。

## 同步上游

```bash
# 1. GitHub 上 main 分支点 “Sync fork”（或 git fetch upstream && git push origin upstream/main:main）
git checkout remix
git fetch origin
git rebase origin/main
git push --force-with-lease origin remix
```
