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
3. ✅ 所有 API 实现（参照 SPEC.md API 设计）
4. ✅ JWT 认证中间件
5. ✅ CORS 跨域配置
6. ✅ `backend/Dockerfile`
7. ✅ `backend/cloudbuild.yaml`（触发器用 REST API 创建）
8. ✅ GitHub push（第一次部署触发器由主 Agent 创建）

## 注意事项

- JWT Secret 使用随机字符串，长度 ≥ 32
- 数据库连接使用环境变量，不要硬编码
- 错误统一封装：`{ "code": 200/401/403/500, "message": "...", "data": ... }`
- 所有密码 BCrypt 加密存储
- Controller 只做参数校验，业务逻辑放 Service 层
