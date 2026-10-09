# V1 Roadmap

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

### Phase 4.1：下一步 Cooking 交互增强（待开发）

这组任务来自已上线食谱产品中反复出现的使用做法，而非沿用项目以前堆出的开发顺序：**Paprika** 的料理计时器/音效/点击时间、**ReciMe** 的食材/温度点击详情、**Crouton / Tamarin** 的单步骤免手操作。详细竞品出处见 [REFERENCES.md](REFERENCES.md#cooking-体验下一阶段参考产品)。

| 优先级 | 开发 Issue | 用户实际得到的能力 | 当前缺口 |
| --- | --- | --- | --- |
| P0 | [#231 Timer sounds](https://github.com/natefox2017/cook/issues/231) | 倒计时接近结束时短促提醒、到点明显提示音；前台与后台统一通知、不双响 | 现有 `TimerNotifications` 只在到点使用系统默认声音 |
| P0 | [#233 Tap parameter details](https://github.com/natefox2017/cook/issues/233) | 点击食材查看当前份量，点击温度查看 °C/°F，点击时长查看/启动对应计时 | `RecipeDetailView` 的 instruction/temperature/timer 信息多为静态 Text/Label |
| P1 | [#232 Hands-free voice controls](https://github.com/natefox2017/cook/issues/232) | Cooking Mode 内主动开麦后，`Next / Previous / Repeat` 语音切步骤/朗读步骤 | 只有触控按钮，没有语音识别及权限状态 |

**交付边界与顺序：** #231 和 #233 可分支并行；#232 在设计音频生命周期时对齐 #231 的 AVAudioSession 策略。每项按 Issue 范围单独 PR、各自验收后合并，避免多名开发者同时重写 `CookingView.swift`。**以上目前仅建任务，未实现、未通过设备验收。**

**兼容性：** 保留多 timer、绝对 deadline、步骤进度/食谱数据、现有四 Tab、免费路径与后端接口。声音遵守 iOS 通知/静音；语音只在 Cooking 前台显式授权监听；参数卡只转换可证明的量，不能猜重量/热量。多语言命令与说明对接 [#230](https://github.com/natefox2017/cook/issues/230)，测试阶段不改变默认英文策略。

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
- 公开分享
- 社区/Feed
- 推荐系统
