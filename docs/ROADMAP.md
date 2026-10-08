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
