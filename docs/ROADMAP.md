# V1 Roadmap

本路线按成熟食谱工具反复出现的真实使用闭环排序：先解决“收进来”，再解决“找得到/看得懂/做得出来”，将购物纳入首个可用闭环，之后补计划（官方证据见 REFERENCES.md；开发先后是 Cook 的推导，不是竞品团队流程披露）。

## Phase 0：产品与协议冻结
- V1 范围与 PRODUCT_BASELINE_V1.md 中 D1–D4 已确认选择落入共享合同
- 导入状态机
- 数据模型
- API 合同（含 D4 账户所有权和可靠本地接收）
- UI 设计确认

Exit：
- 文档无冲突
- UI 核心页面全部有 APPROVED 设计
- import contract 可供 iOS/Backend 并行开发

## Phase 1：收藏闭环
- iOS App 基础壳与 D4 已确认的账户/待登录补传
- Share Extension
- URL/text 导入
- import job API
- queue worker
- source resolver
- duplicate detection

Exit：
第三方 App → 分享 → Cook → “已收下” → 返回，后台能生成最小食谱记录。

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
- 喜欢与食谱册（D1 已确认）
- 待完善
- 详情/编辑
- 原来源跳转

Exit：
导入后的食谱可持续管理和修正。

## Phase 4：真正做饭
- 做饭模式
- 基础份量调整与单计时器（D2 已确认）
- 食材/步骤联动

Exit：
明确/未知数量与时间样例通过 Flow I（D2 已确认）；原始数据不被调整覆盖，计时按真实时间恢复。

## Phase 5：购物闭环
- shopping list
- 安全数量合并
- recipe → grocery
- 已保存食谱离线查看/做饭、购物离线编辑与恢复联网补传

Exit：
USER_FLOWS.md 的 Flow H/I 通过真实 iOS 验收。Phase 1–5 共同组成首个可用闭环，Phase 1 入队不等于产品可用。

## Phase 5b：简单周计划（V1 后段）
- 简单周计划（二级能力）
- meal plan → grocery

## Phase 6：发布前
- 首次账户方案与可靠入队验收（D4，工程合同先冻结）
- 食谱导出与脱离 App 的内容核对（D3）
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

## 跨任务依赖（Issue #7）

- 导入任务：可靠本地接收后才反馈成功、离线补传幂等；保留原份量及非精确食材文本，不能为换算伪造份量。
- 工程任务：按 D1 已确认选择冻结册/食谱关系与喜欢标记；按 D2 已确认选择冻结份量快照/计时截止时间/通知合同；离线持久化与购物冲突策略；D3 已确认导出版本及缺附件清单；D4 已确认登录方案的用户所有权、会话失效补传与退出清理。
- 本任务不修改 DATA_MODEL/API_CONTRACT/架构/设计审批。相关合同有缺口时记录依赖，不各自造字段。
- 设计任务：先登记并取得明确“确认”，覆盖组织、份量、计时、离线失败、导出、首次账户状态；本 PR 没有批准任何 UI。
