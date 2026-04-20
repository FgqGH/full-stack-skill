# 子 Agent 前端开发 Prompt 模板

## 任务描述

请在 `{project-path}/frontend` 下开发 `{project-name}` 系统前端。

## 基础设施

- **GitHub Token**: `{{GITHUB_TOKEN}}`
- **Owner**: `FgqGH`
- **仓库名**: `FgqGH/{repo-name}`
- **API Base URL**: `https://{backend-host}/api`

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
