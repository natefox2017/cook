# GitHub Ruleset Specification

目标：保护 main 分支，保证 Agent 并行开发不会直接破坏主线。

## main branch

建议配置：

- Require pull request before merging
- Require status checks:
  - iOS CI
  - Docs Check
- Require branches to be up to date
- Block force pushes
- Block branch deletion
- Allow auto-merge after checks pass

## Pull Request

所有代码必须：

1. Issue 驱动
2. PR 关联 Issue
3. CI 通过
4. Review 后合并

## Agent Rules

不同 Agent 修改不同目录：

- iOS Agent: ios/
- Backend Agent: supabase/
- AI Agent: ai/
- Docs Agent: docs/

禁止多个 Agent 同时修改同一核心文件。
