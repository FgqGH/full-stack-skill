# 子 Agent 后端开发 Prompt 模板

## 任务描述

请在 `{project-path}` 下开发 `{project-name}` 系统后端。

## 基础设施

- **GitHub Token**: `{{GITHUB_TOKEN}}`
- **Owner**: `FgqGH`
- **仓库名**: `FgqGH/{repo-name}`
- **GCP Project**: `my-project-openclaw-492614`

## 数据库连接

- **Host**: `{db-host}`
- **Port**: `{db-port}`
- **Database**: `{db-name}`
- **User**: `{db-user}`
- **Password**: `{db-password}`

## 技术要求

- **技术栈**: `{tech-stack}`
- **API Base URL**: `https://{backend-host}/api`
- **认证方式**: JWT
- **数据库**: MySQL / PostgreSQL / Supabase

## SPEC.md 要点

```
{spec-content}
```

## 完成标准

1. ✅ 项目骨架（Maven/Node 项目配置）
2. ✅ 数据库建表 SQL（放在 `backend/sql/` 或 Flyway migration）
3. ✅ **`backend/openapi.yaml`** — 完整的 OpenAPI 3.0 契约定义（见 `references/openapi-contract.md`）
4. ✅ 所有 API 实现（参照 SPEC.md API 设计，**必须与 openapi.yaml 完全一致**）
5. ✅ JWT 认证中间件
6. ✅ CORS 跨域配置
7. ✅ `backend/Dockerfile`
8. ✅ `backend/cloudbuild.yaml`（包含 Contract Test step）
9. ✅ GitHub push（第一次部署触发器由主 Agent 创建）

## API 契约规范

**必须先定义 openapi.yaml，再写代码。** 详见 `references/openapi-contract.md`。

关键要求：
- 所有 API 必须定义在 `backend/openapi.yaml` 中
- 统一响应格式：`{ "code": 200, "message": "success", "data": ... }`
- 错误响应：`{ "code": 401/403/404/500, "message": "...", "data": null }`
- HTTP Status Code 遵循：200→成功，201→创建，400→参数错误，401→未认证，404→不存在，500→内部错误
- JWT 在请求头 `Authorization: Bearer <token>` 中传递
- 分页格式：`page`, `pageSize`，返回 `{ list: [], total, page, pageSize }`

## 测试要求

**必须遵循 `references/testing-quality-gate.md` 规范。**

关键要求：
- Controller 层必须有 `@WebMvcTest` 测试（模拟 HTTP 请求）
- Service 层必须有单元测试（Mock 外部依赖）
- 集成测试使用 `@SpringBootTest`（真实 Spring 上下文）
- `pom.xml` 必须配置 JaCoCo，覆盖率门禁：line > 70%
- 测试数据使用 Faker 或随机生成，不用固定值
- 第三方依赖（DB、Redis）用 Testcontainers 隔离
- 所有测试方法命名：`method_condition_expectedResult`
- Contract Test 通过后才会打包部署

## 可观测性规范

**必须遵循 `references/observability.md` 规范。**

关键要求（后端）：
- 所有日志必须为 JSON 格式，包含字段：`timestamp`、`level`、`message`、`correlationId`、`service`、`traceId`、`spanId`、`userId`、`duration`
- 请求入口必须生成/透传 `x-correlation-id`（UUID），写入 MDC 并通过 header 传递到下游
- Spring Boot 使用 Logback JSON Layout（`ch.qos.logback.contrib.json.classic.JsonLayout`）
- Node.js 使用 Pino 日志库
- 集成 OpenTelemetry SDK（`opentelemetry-spring-boot-starter`），自动注入 traceId/spanId 到日志
- `application.yml` 配置 OTel exporter OTLP endpoint（从环境变量 `OTEL_EXPORTER_OTLP_ENDPOINT` 读取）
- 敏感字段（password、token、secret）禁止写入日志
- `health` 端点返回 `{ "status": "UP", "timestamp": "..." }`
- 所有数据库操作记录慢查询（> 500ms 输出 WARN）
- 异常日志必须包含 stackTrace 和 correlationId

## 数据库迁移规范

**必须遵循 `references/database-migration.md` 规范。**

关键要求：
- 迁移文件放在 `backend/src/main/resources/db/migration/`，命名 `V{version}__{description}.sql`
- 每个表结构变更、索引创建必须通过迁移文件管理（不用手动 SQL）
- 迁移必须幂等（`CREATE TABLE IF NOT EXISTS`、`ALTER TABLE ADD COLUMN IF NOT EXISTS` 实现）
- `clean-disabled: true`（生产环境禁止 flyway clean）
- 大表数据迁移分批处理（每批 ≤ 10000 行），避免锁表
- 所有迁移在 dev 环境验证通过后才能合入
