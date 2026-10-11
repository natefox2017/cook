# Cloudflare 部署操作手册

对应 [DEV-317](https://linear.app/gengyun/issue/DEV-317)。本手册说明仓库已有的官网和管理端部署方式；任务状态、发布记录和验收证据保存在 Linear。

## 部署结构

| 应用 | 源码与配置 | Worker | 正式域名 |
| --- | --- | --- | --- |
| 官网 | `web/`、[wrangler.jsonc](wrangler.jsonc) | `recipe-pals-site` | `www.shopkivoo.com`、`shopkivoo.com` |
| 管理端 | `admin/`、[wrangler.jsonc](../admin/wrangler.jsonc) | `recipe-admin` | `admin.shopkivoo.com` |

官网是 Next.js + OpenNext，Workers 执行服务端路由，Workers Assets 提供字体、图片与静态资源。管理端是 Vite/React SPA，Workers Assets 支持 `/admin/*` 深链接；小型 Worker 将指定 `/api/*` 请求转发到 Supabase Edge Functions。

两者独立构建、独立发布。当前配置不需要 R2、KV、D1 或新增付费数据库。Workers 免费计划仍有动态请求、CPU 等限制，具体额度以 Cloudflare 当前套餐页面为准。不要把 `web/dist` 的 Node 服务包当作 Workers 部署产物。

## 准备环境和身份

在仓库根目录开始，使用 Node.js 22+、npm 和 `package-lock.json`，先确认分支、提交及配置是要发布的版本。用 `npm ci` 安装锁定依赖，不单独升级 Wrangler、Next.js 或 OpenNext。

域名需在目标 Cloudflare 账户中，Zone 状态为 Active，注册商的 nameserver 应与 Cloudflare 提供的值一致。两个配置文件的 `account_id` 必须对应同一个实际部署账户。

在 Cloudflare 的 My Profile → API Tokens 创建 Token。当前 Workers/域名部署使用以下权限：

| 类型 | 权限 | 级别 |
| --- | --- | --- |
| Account | Workers Scripts | Edit |
| Account | Account Settings | Read |
| Zone | Zone | Read |
| Zone | Workers Routes | Edit |
| Zone | DNS | Edit |

Account Resources 限定到目标账户，Zone Resources 限定到 `shopkivoo.com`，设置适当到期时间。不要使用全部账户、全部 Zone 或 Global API Key。已有域名绑定后的日常发布可以按实际操作进一步缩小权限。

Token 由 CI 密钥管理或当前 Shell 进程注入 `CLOUDFLARE_API_TOKEN`。本地 Bash 可隐藏输入，避免把值写入命令历史：

```sh
read -r -s -p 'Cloudflare API Token: ' CLOUDFLARE_API_TOKEN
printf '\n'
export CLOUDFLARE_API_TOKEN
export WRANGLER_SEND_METRICS=false
```

发布结束后执行 `unset CLOUDFLARE_API_TOKEN`。不要把 Token 写进源码、Wrangler 的 `vars`、前端 `VITE_*`、README、截图或提交。账户 ID、域名、Supabase Functions URL 是公开配置；部署 Token、管理员密码、会话及服务端密钥不是。

## 发布官网

以下命令从仓库根目录执行：

```sh
cd web
npm ci
npm test
npm run build:cloudflare
npm run preview:cloudflare
```

本地预览默认访问 `http://localhost:8787`；检查后按 Ctrl+C 退出。预览会启动 workerd，不能只用 Node 的 `next start` 代替 Workers 兼容验证。

在 [wrangler.jsonc](wrangler.jsonc) 的 `vars` 中确认：

| 配置 | 作用 |
| --- | --- |
| `RECIPE_PALS_SITE_URL` | 当前为 `https://www.shopkivoo.com`，用于 sitemap 和页面元数据 |
| `RECIPE_PALS_APP_STORE_URL` | 已核实的 App Store HTTPS 链接；未开放时保留空字符串 |
| `RECIPE_PALS_PUBLIC_RECIPE_API` | 经批准的 HTTPS 公共快照 API 根地址，分享页拼接 `/slug`；未接通时保留空字符串 |

[构建脚本](scripts/build-cloudflare.mjs) 读取 Wrangler 的公开 `vars` 并注入 Next.js 构建，这些值优先于同名进程变量。Cloudflare 部署配置变更应改此文件，然后重新构建部署；不要只修改 Node 部署用的 `.env.local`。

```sh
npm run deploy:cloudflare
```

该命令重新构建并发布 `.open-next/worker.js` 和 `.open-next/assets`，同时应用 `routes` 中的两个 Custom Domain。只读静态资源缓存支持构建时页面；当前不支持 ISR 或运行时缓存写入。分享页保持逐次读取 API 和 no-store。

## 发布管理端

从仓库根目录执行：

```sh
cd admin
npm ci
cp .env.example .env.local
```

编辑被 Git 忽略的 `.env.local`：

```dotenv
VITE_ADMIN_FUNCTIONS_URL=/api
VITE_SUPABASE_PUBLISHABLE_KEY=<目标 Supabase 项目的公开 publishable key>
```

占位符必须替换为真实公开 key。可在 Supabase 项目设置的 API Keys 中取得；不能填 secret/service-role key。`VITE_*` 会编译进浏览器 JS，修改后必须重新构建。

[admin/wrangler.jsonc](../admin/wrangler.jsonc) 的 `ADMIN_FUNCTIONS_URL` 是真实服务端转发目的地，当前指向 `semsjyrqjnumpvanibip` 项目。`/api` 是浏览器同源入口，两者作用不同。

```sh
npm run lint
node --test worker.test.mjs tests/revenue.test.mjs
npm run build
npm run preview:cloudflare
```

退出预览后发布：

```sh
npm run deploy:cloudflare
```

该命令重建 `dist/` 并发布管理端 Worker。不要复用官网的 `.open-next/`。

代理仅允许 `admin-auth`、`admin-dashboard`、`admin-users`、`admin-subscriptions`、`admin-ai`；保留管理员 bearer 和公开 apikey，不转发浏览器 cookie。后端必须继续验证管理员会话和角色，不能用代理替代鉴权。

发布前端不会部署 Supabase 函数、执行数据库迁移、初始化 Owner 或重置密码。生产禁止默认 `admin/admin`；使用已初始化 Owner 的凭据。首次初始化或凭据恢复遵循独立的后端运维流程，不通过关闭生产限制解决。Passkey 登录还需后端正确配置 `ADMIN_WEBAUTHN_ORIGIN` 和 `ADMIN_WEBAUTHN_RP_ID`。

## 域名与 HTTPS

Wrangler 的 `routes` 使用 `custom_domain: true`，由 Cloudflare 管理对应 Worker 的 DNS 和证书。首次发布前检查同名 DNS 记录：如有旧站点占用，先确认迁移目标及恢复方式，再处理冲突；不要批量清空 Zone。保留邮箱 MX/TXT 和其他无关子域名。

发布后在 Workers & Pages → 对应 Worker → Settings → Domains & Routes 检查域名，确认 DNS 代理、域名激活和证书签发完成。这里部署的是 Workers，不需要新建 Pages 项目，也不需要填写 Pages 的构建输出目录。

官网的 www 和根域名都绑定同一 Worker；元数据使用 www。配置没有强制根域名 301 跳转，不应把域名双绑定误认为已配置跳转。管理员入口是 `https://admin.shopkivoo.com/admin/login`。

## 发布验证

先确认发布命令成功，并将提交、Worker Version ID 和实际验证结果记录到对应 Linear 发布任务。

官网使用浏览器检查：

- `https://www.shopkivoo.com/` 和 `https://shopkivoo.com/` 可打开，手机宽度无横向溢出，字体和图片正常。
- `/download`、`/privacy`、`/terms`、`/sitemap.xml` 可访问；未填商店地址时明确显示尚未开放。
- `/r/<有效分享字符串>`：已发布快照正常、撤回/不存在不可见、API 故障明确不可用；无真实 API 时不能声称分享已接通。非法字符串返回 404，未配置服务的合法字符串显示不可用并返回 503。
- 分享页保持 `Cache-Control: private, no-store` 和禁索引策略；不要添加 CDN 的 Cache Everything 规则缓存私密/撤回内容。

管理端检查：

- `/admin/login` 可打开；未登录访问 `/admin/users` 或 `/admin/subscriptions` 回到登录页，深链接不会返回资产 404。
- 无管理员 bearer 的受保护 API 拒绝访问，不允许的 `/api/*` 函数返回 404；API 响应保持 no-store，管理端禁止搜索引擎索引。
- 使用获授权的真实账号验证登录、会话刷新及角色允许的页面，收入接口字段不兼容时显示明确错误，页面不能白屏。

HTML 200、构建成功或代理 401 都不能证明真实登录、财务数据、分享流程已经通过。浏览器模拟接口只能证明前端行为；必须区分模拟与真实后端验收。协议草稿、App Store 地址和分享 API 的上线验收仍分别完成。

## 常见故障

| 现象 | 检查和处理 |
| --- | --- |
| Cloudflare 403 / authentication error | 检查 Token 是否过期、账户/Zone 范围及权限；Token 验证有效不等于有部署权限 |
| 域名绑定冲突或 HTTPS 未就绪 | 检查同名 DNS、Zone nameserver、Domains & Routes 及证书状态；保留无关记录 |
| 官网 Node 构建成功但 workerd 500 | 检查锁定的 Next/OpenNext 组合；当前使用 Next `15.5.27`、OpenNext `1.20.10`，升级需重新验证 workerd，不能直接改到不受支持版本 |
| 管理端提示未配置 | 检查构建时的两个 `VITE_*`，补齐后重建发布；运行时 Worker `vars` 不能修补已编译的浏览器配置 |
| `/api/*` 502 | 检查 Supabase 可用性、目的 URL、30 秒超时和 Worker 日志；代理拒绝重定向。Workers fetch 使用 `redirect: manual` 并检查 3xx，不能改成不受支持的 `redirect: error` |
| Revenue 提示 billing service needs an update | 部署的后端缺少当前 currency-aware 响应字段；按独立后端发布流程更新，不能伪造 USD、补零或隐藏成成功 |
| 默认管理员凭据被禁用 | 使用已初始化 Owner 密码；需要恢复时走后端运维流程，不删除生产保护 |
| 更新后仍是旧页面 | 刷新浏览器，核对 HTML 引用的新 hash JS 和 Worker 部署版本；先排查额外缓存规则，不批量清空所有缓存 |

必要时在对应目录执行 `npx wrangler tail` 查看日志，结束后 Ctrl+C。日志可能含请求信息；不粘贴密码、请求体、授权头或用户隐私到任务/PR。

## 回滚

发布前在 Cloudflare Worker 的 Deployments 页面确认上一稳定版本及其对应提交。发布出现故障时，选择该 Worker 的上一稳定版本执行 Rollback，完成后重新检查域名、静态资源、深链接和相关 API。也可在对应应用目录按 Wrangler 支持的语法执行：

```sh
npx wrangler rollback <上一稳定的Worker版本ID>
```

Workers 版本回滚不等于回滚 DNS、Custom Domain、外部 Supabase 函数或数据库；这些变更需各自的恢复方案。确认目标版本的静态资产仍可用；如历史版本不可回滚，从该稳定提交的独立 checkout 安装锁定依赖，用匹配的公开配置重建发布。不要在共享工作目录用 `git reset --hard` 覆盖其他人的修改。

官网和管理端分别回滚，回滚后记录版本、原因和实际验证。后续再从修复后的 main 正常发布，避免只在 Cloudflare 控制台长期保留与仓库不一致的配置。
