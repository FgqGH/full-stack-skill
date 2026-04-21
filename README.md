# full-stack-skill

> Hermes Agent 全栈开发自动化框架 — 从需求到上线的完整工程化流程。

## 是什么

本仓库是 [Hermes Agent](https://github.com/FgqGH/hermes-agent) 的**全栈开发技能模块**。当你对 Hermes 说"帮我做一个完整系统"时，Hermes 加载本技能，自动完成从需求分析到生产部署的全流程，零手动操作。

## 核心流程

```
需求输入
    ↓
① SPEC.md + openapi.yaml（契约先行）
    ↓
② 技术选型（简单 → HTML/JS + Node.js，复杂 → Flutter Web + Spring Boot）
    ↓
③ 前端 + 后端 subagent 并行开发
    ↓
④ GitHub push 触发器创建（REST API，路径过滤）
    ↓
⑤ Cloud Build 自动化构建
    ├─ 后端：Contract Test → 单元测试/覆盖率 → Flyway 迁移 → Docker → Cloud Run
    └─ 前端：Flutter Build → Widget Test → Lighthouse CI → Docker → Cloud Run
    ↓
⑥ Smoke Test + 自动回滚（失败即回滚）
    ↓
⑦ OTel 可观测性 + Cloud Monitoring 监控告警
    ↓
返回：前端 URL + 后端 API URL
```

## 目录结构

```
full-stack-skill/
├── SKILL.md                        # 主技能文件（Hermes Agent 读取）
├── README.md                       # 本文件
├── scripts/
│   └── gcp-init.sh                 # GCP 项目初始化脚本（幂等）
└── references/
    ├── create-trigger.sh           # Cloud Build 触发器创建脚本（幂等）
    ├── openapi-contract.md         # OpenAPI 3.0 契约开发规范
    ├── testing-quality-gate.md     # 测试体系 + 覆盖率门禁
    ├── observability.md            # 可观测性规范（结构化日志/OTel/告警）
    ├── database-migration.md       # Flyway 数据库迁移规范
    ├── subagent-backend-prompt.md  # 后端 subagent prompt 模板
    └── subagent-frontend-prompt.md # 前端 subagent prompt 模板
```

## 技术栈支持

| 场景 | 前端 | 后端 | 数据库 |
|------|------|------|--------|
| 快速验证 / H5 | HTML/JS | Node.js + Express | Supabase |
| 多角色 / 复杂状态 | Flutter Web | Spring Boot | MySQL / Cloud SQL |
| 内容展示为主 | HTML/JS | Node.js + Express | Supabase |

## 安全原则

- **所有 secrets（密码、JWT_SECRET）通过 GCP Secret Manager 管理**，不写入 cloudbuild.yaml 环境变量
- **所有数据库密码通过 Cloud Build 内置 `availableSecrets.secretManager` 注入**，不落地磁盘，不进日志
- **路径过滤**：触发器配置 `pathFilters`，避免后端变更触发前端构建

## 质量门禁

- Contract Test（prism + dredd）：API 契约 100% 路径覆盖
- 单元测试 + 覆盖率（JaCoCo > 70%，Istanbul > 70%）
- Lighthouse CI Performance > 90（Flutter Web）
- Smoke Test + Auto Rollback（部署失败自动回滚）
- Flyway 迁移 fail-fast（迁移失败阻断部署）

## GCP 基础设施

| 资源 | 值 |
|------|-----|
| Project | `my-project-openclaw-492614` |
| Region | `asia-east1` |
| Artifact Registry | `asia-east1-docker.pkg.dev/my-project-openclaw-492614` |
| deploy-bot | `deploy-bot@my-project-openclaw-492614.iam.gserviceaccount.com` |
| Secrets | `JWT_SECRET`、`DB_PASSWORD`（存入 Secret Manager）|

## 快速开始

### 1. 初始化 GCP 环境（首次）

```bash
chmod +x scripts/gcp-init.sh
./scripts/gcp-init.sh my-project-openclaw-492614
```

### 2. 开始新项目

```
对 Hermes 说：
"做一个图书馆管理系统，包含用户登录、图书管理、借阅管理模块"
```

### 3. 查看项目进度

```bash
cat ~/.openclaw/workspace/projects/<project-name>/.task-state.json
```

## 关键脚本

| 脚本 | 作用 | 幂等 |
|------|------|------|
| `scripts/gcp-init.sh` | GCP 项目初始化（API/SA/角色/Secret/Artifact Registry） | ✅ |
| `references/create-trigger.sh` | 创建 GitHub → Cloud Build 触发器 | ✅ |

## 相关文档

- [OpenAPI 契约开发规范](references/openapi-contract.md)
- [测试体系与质量门禁](references/testing-quality-gate.md)
- [可观测性规范](references/observability.md)
- [数据库迁移规范](references/database-migration.md)
