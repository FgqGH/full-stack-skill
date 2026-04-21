# 子 Agent 前端开发 Prompt 模板

## 任务描述

请在 `{project-path}/frontend` 下开发 `{project-name}` 系统前端。

## 基础设施

- **GitHub Token**: `{{GITHUB_TOKEN}}`
- **Owner**: `FgqGH`
- **仓库名**: `FgqGH/{repo-name}`
- **API Base URL**: `https://{backend-host}/api`

## API 契约规范

**必须基于 `backend/openapi.yaml` 开发前端 API 调用。** 详见 `references/openapi-contract.md`。

前端开发阶段使用 Mock Server：
```bash
# 启动 mock server
prism mock backend/openapi.yaml --port 4010

# 前端 .env 配置
VITE_API_BASE_URL=http://localhost:4010/api
```

关键要求：
- 所有 API 调用使用 `VITE_API_BASE_URL` 环境变量（开发用 mock，生产的 `API_URL`）
- 接口字段与 openapi.yaml 中 schemas 定义完全一致
- 统一响应格式：`{ code, message, data }`，其中 `code=200` 为成功
- 错误处理：所有 HTTP 错误码和业务错误码都要处理
- 分页参数 `page`, `pageSize`，返回 `{ list: [], total, page, pageSize }`
- JWT Token 存储在 localStorage，通过拦截器自动注入：`Authorization: Bearer <token>`
- `401` 响应 → 清除 Token 跳转登录页

## 技术要求

- **Flutter 版本**: 3.24.5
- **状态管理**: Riverpod
- **路由**: GoRouter
- **HTTP 客户端**: Dio
- **构建目标**: Web（`flutter build web`）

## API 配置（Dio）

```dart
static const String baseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://{backend-host}/api',
);
```

构建命令：`flutter build web --dart-define=API_URL=https://{backend-host}/api`

## SPEC.md 页面需求

```
{pages-list}
```

## 完成标准

1. ✅ Flutter 项目初始化（`flutter create frontend`）
2. ✅ 路由配置（GoRouter，含管理员/用户角色区分）
3. ✅ Dio HTTP 客户端（含 JWT Token 自动注入拦截器）
4. ✅ 所有页面实现（参照 SPEC.md 页面结构）
5. ✅ Riverpod 状态管理（AsyncNotifierProvider 用于 API 数据）
6. ✅ `frontend/Dockerfile.nginx`
7. ✅ `frontend/nginx.conf`
8. ✅ `frontend/cloudbuild.yaml`
9. ✅ GitHub push（触发器由主 Agent 创建）

## 测试要求

**必须遵循 `references/testing-quality-gate.md` 规范。**

关键要求：
- 每个页面必须有 Widget Test（render + interaction）
- 关键用户流程必须有 Integration Test
- API 调用层必须 Mock Dio（不用真实网络）
- `pubspec.yaml` 必须添加 `integration_test` 和 `mockito`
- 测试数据用 Faker 或 mockito 生成，不用固定值
- Lighthouse CI Performance > 90

## 可观测性规范

**必须遵循 `references/observability.md` 规范。**

关键要求（前端）：
- 前端发起所有 HTTP 请求时自动注入 `x-correlation-id` header（若无则生成 UUID）
- 全局 `window.onerror` 和 `unhandledrejection` 事件捕获错误并记录到 `window.logger`
- `window.logger` 在生产环境将错误上报到后端日志服务（POST `/api/logs/client`）
- ErrorBoundary 组件捕获 React 渲染错误，显示友好降级 UI 并记录错误
- 关键性能指标监控：LCP > 2.5s、FID > 100ms、CLS > 0.1（通过 `web-vitals` 库）
- 生产环境通过 Lighthouse CI 持续监控 Performance score，目标 > 90
- 所有 API 错误（4xx/5xx）在 UI 上显示用户友好的错误提示，不暴露内部细节
- Loading 状态必须有 skeleton/spinner，禁止裸 loading 文字

## Flutter Web 注意事项

- `uses-material-design: true`（pubspec.yaml）
- 所有静态 widget 使用 `const` 构造器
- 异步操作后检查 `mounted`
- `ListView.builder` 用于长列表
- Dio Token 拦截器：`options.headers['Authorization'] = 'Bearer $token'`
- 错误处理：`401` → 清除 Token 跳转登录页

## Nginx 配置要点

```nginx
location /api/ {
    proxy_pass https://{backend-host}/api/;
    proxy_set_header Host {backend-host};
}
```
