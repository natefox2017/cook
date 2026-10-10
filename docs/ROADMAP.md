# V1 Roadmap

> 本文只维护长期产品范围、交互与技术设计，不维护任务状态或开发进度；任务、依赖和验收以 [Linear DEV Recipe Pals Development](https://linear.app/gengyun/project/recipe-pals-development-8c015c72cb6a) 为准。

本路线按成熟食谱工具反复出现的真实使用闭环排序：先解决“收进来”，再解决“找得到/看得懂/做得出来”，最后补购物与计划。

## Phase 0：产品与协议冻结
- V1 范围
- 导入状态机
- 数据模型
- API 合同
- UI 设计确认

Exit：
- 文档无冲突
- UI 核心页面全部有 APPROVED 设计
- import contract 可供 iOS/Backend 并行开发

## Phase 1：收藏闭环
- iOS App 基础壳
- Share Extension
- URL/text 导入
- import job API
- queue worker
- source resolver
- duplicate detection

Exit：
第三方 App → 分享 → Recipe → “已收下” → 返回，后台能生成最小食谱记录。

## Phase 2：AI 结构化
- caption/article extraction
- ASR
- OCR/key-frame evidence
- parser/normalizer
- quality validator
- needs_review

Exit：
可稳定输出带来源证据的 ingredients/steps；不伪造精确值。

## Phase 3：私人食谱库
- 食谱库
- 搜索
- 收藏
- 待完善
- 详情/编辑
- 原来源跳转

Exit：
导入后的食谱可持续管理和修正。

## Phase 4：真正做饭
- 做饭模式
- 份量调整
- 计时器
- 食材/步骤联动

### Phase 4.1：Cooking 交互增强

这组任务来自已上线食谱产品中反复出现的使用做法，而非沿用项目以前堆出的开发顺序：**Paprika** 的料理计时器/音效/点击时间、**ReciMe** 的食材/温度点击详情、**Crouton / Tamarin** 的单步骤免手操作。详细竞品出处见 [REFERENCES.md](REFERENCES.md#cooking-体验下一阶段参考产品)。

| 产品优先级 | 对应 Linear Issue | 用户实际得到的能力 | 设计与兼容约束 |
| --- | --- | --- | --- |
| P0 | [DEV-86 Timer sounds](https://linear.app/gengyun/issue/DEV-86) | 倒计时接近结束时短促提醒、到点明显提示音；前台与后台统一通知、不双响 | 复用 `TimerNotifications`；前后台提醒去重与系统静音约束 |
| P0 | [DEV-81 Tap parameter details](https://linear.app/gengyun/issue/DEV-81) | 点击食材查看当前份量，点击温度查看 °C/°F，点击时长查看/启动对应计时 | 复用 `RecipeDetailView` 并保留无证据数量/单位的原始信息 |
| P1 | [DEV-84 Hands-free voice controls](https://linear.app/gengyun/issue/DEV-84) | Cooking Mode 内主动开麦后，`Next / Previous / Repeat` 语音切步骤/朗读步骤 | 保留触控回退；语音仅前台自愿启用并正确处理权限 |

**交付边界与顺序：** DEV-86 和 DEV-81 可分支并行；DEV-84 在设计音频生命周期时对齐 DEV-86 的 AVAudioSession 策略。每项按 Issue 范围单独 PR、各自验收后合并，避免多名开发者同时重写 `CookingView.swift`。**具体实现和真机验收以对应 Linear Issue 的实时记录为准。**

**兼容性：** 保留多 timer、绝对 deadline、步骤进度/食谱数据、现有四 Tab、免费路径与后端接口。声音遵守 iOS 通知/静音；语音只在 Cooking 前台显式授权监听；参数卡只转换可证明的量，不能猜重量/热量。多语言命令与说明对接 [DEV-88](https://linear.app/gengyun/issue/DEV-88)，测试阶段不改变默认英文策略。

### Phase 4.2：可验证的 AI 食谱生成与修改

优先依据已上线 **ReciMe 一键导入 + Honeydew AI Edit** 的重复产品实践，而不是沿用旧试验性流程。详见 [AI 体验方案](PRODUCT/AI_RECIPE_EXPERIENCE_2026-10-09.md)。

| 优先级 | Issue | 交付边界 |
| --- | --- | --- |
| P0 | [DEV-79 对话式 AI 食谱草稿](https://linear.app/gengyun/issue/DEV-79) | 导入后根据证据生成草稿，必要时仅追问缺项；同意后入私人库/人工继续编辑 |
| P0 | [DEV-76 食材智能替换与版本对比](https://linear.app/gengyun/issue/DEV-76) | AI 提议修改、预览/应用/保存变体/撤销；无证据不得伪造含量 |
| P1 | [DEV-78 合法视频音频/字幕/关键帧](https://linear.app/gengyun/issue/DEV-78) | 公开/授权来源分层提取，保留时间戳证据；登录墙/DRM 不绕过 |
| P1 | [DEV-77 一来源识别多道菜](https://linear.app/gengyun/issue/DEV-77) | 只在多个候选有证据时展示选择，幂等拆分入库 |

依赖：DEV-78 遵循 DEV-79 的 evidence 合同，DEV-77 可先使用一页多道 JSON-LD 数据、稍后加入视频段落；DEV-76 不必等待所有平台视频支持。**用户保存和用户确认的内容优先于 AI，完整导入不强制用户聊天。**

### Phase 4.3：食谱详情专业化

对照已上线 Samsung Food / ReciMe / Paprika 的页面，而不是堆更多小字。详见 [详情对比审查](PRODUCT/RECIPE_DETAIL_COMPETITOR_AUDIT_2026-10-09.md)。

- P0 [DEV-52 补充可选元数据与兼容模型](https://linear.app/gengyun/issue/DEV-52)：难度、菜系、标签、食材分组、厨具、步骤图片、可信营养等；缺失不猜。
- P0 [DEV-51 专业详情 UI 和功能入口](https://linear.app/gengyun/issue/DEV-51)：第一屏重点信息、可读步骤、AI Edit、Share，保持 Cooking 固定 CTA。
- 已规划 [DEV-81 参数信息弹层](https://linear.app/gengyun/issue/DEV-81)、[DEV-86 计时音效](https://linear.app/gengyun/issue/DEV-86)、[DEV-84 语音控制](https://linear.app/gengyun/issue/DEV-84) 原 Issue 继续；禁止重复另实现。

### Phase 4.4：用户授权分享 → 精美图片 → 公开 Web → 邀请增长（非社区）

参考 [Samsung Food 以**链接/短信/邮件/社交**分享、无账号可读网页](https://support.samsungfood.com/hc/en-us/articles/18588679568532-How-to-Share-Your-Saved-Recipes-with-Anyone)，分享图片二维码为辅助入口。详见 [公开分享与归因决策](PRODUCT/RECIPE_PUBLIC_SHARING_V1.md)。

1. P0 [DEV-73 私人默认、授权发布、公开快照、撤回](https://linear.app/gengyun/issue/DEV-73)：**必须先完成**，强制版权/图片授权边界。
2. P0 [DEV-71 无需安装的 Web 食谱详情、做菜步骤、App CTA](https://linear.app/gengyun/issue/DEV-71)：依赖 DEV-73，域名真实确认后加 Universal Links 和 Smart App Banner。
3. P0 [DEV-68 食谱长图、多尺寸模板、二维码、系统分享](https://linear.app/gengyun/issue/DEV-68)：依赖 DEV-73/243；iPhone 同屏收图时可点击链接，不强制扫描二维码。
4. P1 [DEV-66 首方事件和显式邀请码归因](https://linear.app/gengyun/issue/DEV-66)：先测聚合访问/CTA，再由用户自愿绑定邀请人；App Store 转跳不保证逐人归因。
5. P2 [DEV-64 邀请奖励/反作弊](https://linear.app/gengyun/issue/DEV-64)：**后续单独审批**成本、资格、Apple 规则后才能发奖励；扫码/安装点击不能直接算成功邀请。

**优先交付的闭环**：用户从私有 Recipe Detail 明确发布 → URL 不登录可看授权步骤 → 分享长图/二维码 → 访客可选择下载；后续才做归因和奖励。默认不公开、不自动发送邮件、不创建 Feed/点赞/关注。功能规划不能替代代码、真机或生产验收。

## Phase 5：购物与简单计划
- shopping list
- 安全数量合并
- recipe → grocery
- 简单周计划
- meal plan → grocery

## Phase 6：发布前
- 隐私/数据删除
- RLS/安全审计
- 导入 fixture 回归
- 性能/崩溃
- App Store 上架材料

## 后续版本再评估
- Android
- Mac/iPad 专门布局
- 家庭协作
- 默认公开的菜谱社区 / Feed（独立决定，当前未批准）
- 推荐系统

## 上线条件与发布依赖

- 本路线定义产品能力及其依赖意图，具体 Issue 状态、负责人、执行优先级和验收证据均从 [Linear DEV 项目](https://linear.app/gengyun/project/recipe-pals-development-8c015c72cb6a) 实时读取。
- **代码合并不等于上线许可。** AI 导入、单食谱公开分享和归因相关能力需要先满足 [DEV-50 受控 staging](https://linear.app/gengyun/issue/DEV-50) 的 Auth/RLS/内容授权/撤回验证，最终进入 [DEV-49 发布验收](https://linear.app/gengyun/issue/DEV-49)，获取已签名 App、Web、StoreKit 等适用证据。
- 邀请奖励必须另行授权，不得凭安装点击或二维码扫描认定用户身份或自动发奖。
