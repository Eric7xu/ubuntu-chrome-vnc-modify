# Ubuntu Chrome VNC

在无桌面环境的 Ubuntu 主机上，用 Docker 运行一个可视化 Chrome：

`Xvfb → Openbox → Chrome → x11vnc → noVNC`，并提供本机限定的 CDP 端口。

典型用途是先通过 VNC/noVNC 手动登录，再让 Playwright、`browser-harness` 或其他 CDP 客户端复用持久化的 Chrome profile。

本项目是在参考 [dockcy/ubuntu-chrome-vnc-docker](https://github.com/dockcy/ubuntu-chrome-vnc-docker) 的基础思路上，针对默认公网暴露、空密码启动和进程管理问题做的独立改造版本。

## 安全边界

VNC、noVNC 和 CDP 默认只映射到宿主机 `127.0.0.1`，不会直接监听公网地址。不要把 Compose 中的绑定地址改成 `0.0.0.0`，除非已经在外层配置了 VPN、访问控制和 HTTPS。

CDP 没有独立认证，能够完全控制 Chrome；远程使用请建立 SSH tunnel：

```bash
ssh -N -L 18080:127.0.0.1:18080 -L 9223:127.0.0.1:9223 user@server
```

然后访问 `http://127.0.0.1:18080/vnc.html`。启动必须配置至少 8 个字符的 `VNC_PASSWORD`，空密码会直接失败。

## 启动

```bash
cp .env.example .env
# 编辑 .env，设置随机且未在别处复用的 VNC_PASSWORD
docker compose up -d --build
docker compose logs -f browser
```

查看运行状态：

```bash
docker compose ps
curl http://127.0.0.1:9223/json/version
```

Compose 的 healthcheck 会持续检查 Chrome CDP；如果核心进程退出，容器会退出并由 `restart: unless-stopped` 拉起。

首次启动后通过 noVNC 登录网站。登录状态保存在 Docker volume `chrome_profile` 中。

## CDP

宿主机本地连接：

```bash
curl http://127.0.0.1:9223/json/version
BU_CDP_URL=http://127.0.0.1:9223 browser-harness
```

## 限制

- 当前使用 Google 官方 `amd64` Chrome `.deb`，ARM64/其他架构会在构建阶段明确失败。
- 容器仍然需要约 2GB 共享内存；实际内存建议至少 4GB。
- 这是单浏览器实例，不提供多租户隔离、审计、账号管理或公网身份认证。
- 不要把网络抓包、Cookie 或表单数据写入公开目录。
