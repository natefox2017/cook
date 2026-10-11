# Recipe Pals 官方网站

本官网实现对应 [DEV-308](https://linear.app/gengyun/issue/DEV-308)。架构决策见 [ARCHITECTURE.md](ARCHITECTURE.md)。所有官网源码、配置、文档、测试及运行脚本均在 `web/` 中；公共快照校验、旧阅读器和邀请模块合并到 `lib/`，只有一个 package.json 和一个启动入口。

## 开发

要求 Node.js 22+、npm；打包还需要 `tar`。默认用户界面为英文，与当前 APP 发布语言规范一致。

```sh
bash web/run.sh
```

脚本从任意工作目录定位 `web/`，缺少依赖时自动运行 `npm ci`，首次创建 `.env.local`。不会执行配置文件中的 Shell 命令。

```sh
bash web/run.sh test     # 所有官网与旧 Web 模块测试
bash web/run.sh build    # 生产构建
bash web/run.sh package  # 构建并打包
bash web/run.sh start    # 生产启动，首次无构建时自动构建
```

这里是 Bash `.sh` 一键运行脚本，可在 SSH 登录后的服务器执行；它不主动连接远程服务器，不需要 SSH 密码或私钥。

浏览器打开 `http://localhost:3000`。在 `.env.local` 中配置真实服务信息后重启开发进程。

| 配置 | 说明 |
| --- | --- |
| `RECIPE_PALS_SITE_URL` | 官网 HTTPS 根域名，无路径、查询参数、凭据或端口；用于 sitemap，修改后重新构建 |
| `RECIPE_PALS_APP_STORE_URL` | 已核实的 `https://apps.apple.com/.../id数字`；运行时读取；空值或非法值时显示下载未开放 |
| `RECIPE_PALS_PUBLIC_RECIPE_API` | 经批准的 HTTPS 公共快照 API 根地址，末尾拼接 `/字符串`；运行时读取，不支持凭据、IP、端口、查询参数或重定向 |
| `PORT` | 部署端口，默认 3000 |
| `RECIPE_PALS_BIND_HOST` | 部署包监听地址，默认 `0.0.0.0` |

本站不需要 Supabase service-role、用户 token 或 AI key。不要设置这些秘密。

## 验证与打包

```sh
npm test
npm run package
```

`npm run package` 先构建 Next.js，再生成：

- `dist/recipe-pals-site/`：独立 Node 服务，包括必要依赖、本地字体、图片和静态资源。
- `dist/recipe-pals-site.tar.gz`：可上传的部署包。

脚本排除所有实际 `.env` 配置文件，只保留 `.env.example`。下载链接和公共 API 在部署服务器运行时设置；官网域名在构建时设置。构建不调用菜谱 API。

```sh
tar -xzf recipe-pals-site.tar.gz
cd recipe-pals-site
# 创建 .env，按 .env.example 填入实际配置；不要把真实配置提交到 Git。
bash run.sh start
```

也可以由服务管理器注入环境变量后直接 `node start.mjs`。外层 Nginx/托管平台终止 TLS，代理到 Node 端口。保持 `/r/*` 的 `Cache-Control: private, no-store` 和 `X-Robots-Tag`；关闭 CDN 对这些路径的页面缓存。不是直接上传到静态 CDN 的 `out/` 包。

## 发布配置

隐私协议和用户协议目前明确标记为待审核草稿，尚缺运营主体、联系地址、生效日期、真实处理商/留存政策和法律审核。下载链接未配置时不会生成假的商店链接。正式发布前替换草稿、补齐真实域名和商店链接，并按 DEV-71 / DEV-73 的分享验收要求验证已发布、已撤回和服务故障的访客访问。源码和本地构建不等于 APP、公开 API 或官网已上线。

## 素材

Lora 和 OFL 原样复用 `ios/Recipe/Resources/Fonts`；图标及虾仁意面图原样复用 APP 中的 `RecipeBrand` 和 `OnboardingShrimpPasta` 资源。首页图片是产品展示素材，不用于声称某个用户分享菜谱的成品图。公开快照不包含图片，分享页不会伪造图片。
