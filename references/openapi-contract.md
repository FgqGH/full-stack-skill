# API 契约规范 — OpenAPI 3.0 Contract-First 开发流程

## 核心原则

**Contract-First（契约优先）**：先定义 API 契约（openapi.yaml），前后端各自基于契约独立开发，通过 mock server 和 contract test 做集成验证。

---

## 1. OpenAPI 规范文件结构

每个后端项目必须在 `backend/openapi.yaml` 提供完整的 OpenAPI 3.0 定义。

### 必须包含的章节

```yaml
openapi: 3.0.3
info:
  title: {项目名} API
  version: 1.0.0
  description: |
    {项目描述}
    Base URL: https://{backend-host}/api

servers:
  - url: https://{backend-host}/api
    description: Production

paths:
  # ============ 认证模块 ============
  /auth/login:
    post:
      operationId: login
      summary: 用户登录
      tags: [Auth]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/LoginRequest'
            example:
              username: "admin"
              password: "password123"
      responses:
        '200':
          description: 登录成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/LoginResponse'
        '401':
          description: 用户名或密码错误
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'

  /auth/register:
    post:
      operationId: register
      summary: 用户注册
      tags: [Auth]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/RegisterRequest'
      responses:
        '201':
          description: 注册成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/RegisterResponse'
        '409':
          description: 用户名已存在
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'

  # ============ 用户模块 ============
  /users:
    get:
      operationId: listUsers
      summary: 获取用户列表
      tags: [Users]
      security:
        - bearerAuth: []
      parameters:
        - $ref: '#/components/parameters/Page'
        - $ref: '#/components/parameters/PageSize'
        - name: search
          in: query
          schema:
            type: string
          description: 按用户名/邮箱搜索
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/UserListResponse'

  /users/{id}:
    get:
      operationId: getUser
      summary: 获取用户详情
      tags: [Users]
      security:
        - bearerAuth: []
      parameters:
        - $ref: '#/components/parameters/Id'
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/UserResponse'
        '404':
          $ref: '#/components/responses/NotFound'

# ============ Components ============
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
      description: JWT token（登录后获取）

  parameters:
    Id:
      name: id
      in: path
      required: true
      schema:
        type: integer
        format: int64
      example: 1
    Page:
      name: page
      in: query
      schema:
        type: integer
        default: 1
        minimum: 1
    PageSize:
      name: pageSize
      in: query
      schema:
        type: integer
        default: 20
        minimum: 1
        maximum: 100

  responses:
    NotFound:
      description: 资源不存在
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
    Unauthorized:
      description: 未认证或 Token 过期
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'

  schemas:
    # ============ 认证相关 ============
    LoginRequest:
      type: object
      required: [username, password]
      properties:
        username:
          type: string
          minLength: 3
          maxLength: 50
          example: "admin"
        password:
          type: string
          minLength: 6
          maxLength: 128
          example: "password123"
      description: 登录请求

    LoginResponse:
      type: object
      properties:
        code:
          type: integer
          example: 200
        message:
          type: string
          example: "登录成功"
        data:
          type: object
          properties:
            token:
              type: string
              description: JWT access token
              example: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
            expiresIn:
              type: integer
              description: 有效期（秒）
              example: 86400
            user:
              $ref: '#/components/schemas/User'

    RegisterRequest:
      type: object
      required: [username, password, email]
      properties:
        username:
          type: string
          minLength: 3
          maxLength: 50
          pattern: "^[a-zA-Z0-9_]+$"
          example: "newuser"
        password:
          type: string
          minLength: 6
          maxLength: 128
          writeOnly: true
          example: "password123"
        email:
          type: string
          format: email
          example: "user@example.com"
        role:
          type: string
          enum: [USER, ADMIN]
          default: USER

    RegisterResponse:
      type: object
      properties:
        code:
          type: integer
          example: 201
        message:
          type: string
          example: "注册成功"
        data:
          type: object
          properties:
            userId:
              type: integer
              format: int64
              example: 1

    # ============ 用户相关 ============
    User:
      type: object
      properties:
        id:
          type: integer
          format: int64
          example: 1
        username:
          type: string
          example: "admin"
        email:
          type: string
          format: email
          example: "admin@example.com"
        role:
          type: string
          enum: [USER, ADMIN]
          example: "ADMIN"
        createdAt:
          type: string
          format: date-time
          example: "2024-01-01T00:00:00Z"
        updatedAt:
          type: string
          format: date-time
          example: "2024-01-01T00:00:00Z"
        password:
          type: string
          readOnly: true
          description: 不返回密码

    UserListResponse:
      type: object
      properties:
        code:
          type: integer
          example: 200
        message:
          type: string
          example: "success"
        data:
          type: object
          properties:
            list:
              type: array
              items:
                $ref: '#/components/schemas/User'
            total:
              type: integer
              example: 100
            page:
              type: integer
              example: 1
            pageSize:
              type: integer
              example: 20

    UserResponse:
      type: object
      properties:
        code:
          type: integer
          example: 200
        message:
          type: string
          example: "success"
        data:
          $ref: '#/components/schemas/User'

    # ============ 通用 ============
    ErrorResponse:
      type: object
      properties:
        code:
          type: integer
          description: |
            错误码：
            400 - 参数错误
            401 - 未认证
            403 - 无权限
            404 - 资源不存在
            409 - 冲突（如用户名已存在）
            500 - 服务器内部错误
          example: 401
        message:
          type: string
          description: 错误描述（用于调试，UI 不直接展示）
          example: "用户名或密码错误"
        data:
          type: object
          nullable: true
          description: 错误详情（可选）
```

---

## 2. 统一响应格式

所有 API **必须**遵循以下统一响应格式：

```json
// 成功
{
  "code": 200,
  "message": "success",
  "data": { ... }
}

// 分页列表
{
  "code": 200,
  "message": "success",
  "data": {
    "list": [...],
    "total": 100,
    "page": 1,
    "pageSize": 20
  }
}

// 错误
{
  "code": 400,
  "message": "参数错误",
  "data": null
}
```

### HTTP Status Code 映射

| 业务 Code | HTTP Status | 场景 |
|-----------|-------------|------|
| 200 | 200 | 成功 |
| 201 | 201 | 创建成功 |
| 400 | 400 | 参数错误 |
| 401 | 401 | 未认证 |
| 403 | 403 | 无权限 |
| 404 | 404 | 资源不存在 |
| 409 | 409 | 冲突（用户名重复等） |
| 500 | 500 | 服务器内部错误 |

---

## 3. 错误码规范

```yaml
# 通用错误码（所有模块共用）
COMMON_INVALID_PARAMS: 40001  # 参数校验失败
COMMON_UNAUTHORIZED: 40101    # 未登录或 Token 无效
COMMON_FORBIDDEN: 40301       # 无权限
COMMON_NOT_FOUND: 40401       # 资源不存在
COMMON_CONFLICT: 40901        # 资源冲突
COMMON_INTERNAL_ERROR: 50001  # 服务器内部错误

# 认证模块（Auth，偏移 1000）
AUTH_INVALID_CREDENTIALS: 40101  # 用户名或密码错误
AUTH_USER_EXISTS: 40901          # 用户名已存在
AUTH_TOKEN_EXPIRED: 40102        # Token 已过期

# 用户模块（Users，偏移 2000）
USERS_NOT_FOUND: 40401  # 用户不存在
```

---

## 4. Mock Server 使用流程

### 前端开发阶段使用 Mock

```bash
# 全局安装 prism（OpenAPI mock server）
npm install -g @stoplight/prism

# 启动 mock server（读取后端的 openapi.yaml）
prism mock backend/openapi.yaml --port 4010

# 前端开发时请求 http://localhost:4010
# 示例：请求 http://localhost:4010/api/auth/login
```

### 前端 .env 配置

```env
# 开发环境用 mock
VITE_API_BASE_URL=http://localhost:4010/api

# 生产环境用真实后端
VITE_API_BASE_URL=https://{backend-host}/api
```

---

## 5. Contract Test（Dredd）

在 Cloud Build 中集成 API contract 测试，**前后端任何一方 API 变更都会被检测到**。

### 安装 Dredd Hooks Template

```bash
# 后端项目安装 dredd
npm install -g dredd

# 后端项目添加 dredd 配置文件 dredd.yml
```

### `backend/dredd.yml` 配置

```yaml
reporter: cli
newline: true
color: true
sort: true
inline-errors: false
details: false
method: []
only: []
header: []
user: null
token: null
-endpoint: http://localhost:4010

language: node
features: backend/openapi.yaml
```

### Cloud Build 集成 Contract Test

在 `backend/cloudbuild.yaml` 的 Test step **之前**添加：

```yaml
steps:
  # 0. 启动 Mock Server（使用 prism）
  - name: node:20
    id: Start Mock Server
    entrypoint: npx
    args:
      - "@stoplight/prism"
      - mock"
      - backend/openapi.yaml
      - --port"
      - "4010"
    background: true
    waitFor: ["-"]

  # 1. 运行 Contract Test（mock server 启动后才执行）
  - name: node:20
    id: Contract Test
    entrypoint: npx
    args:
      - dredd
      - backend/openapi.yaml
      - http://localhost:4010
      - --config
      - backend/dredd.yml
    waitFor: [Start Mock Server]

  # 2. 单元测试
  - name: maven:3.9-eclipse-temurin-17
    id: Test
    entrypoint: mvn
    args: [test, -q]
    dir: backend
    waitFor: [Contract Test]
```

> **注意**：Contract Test 在单元测试**之前**执行，确保 API 契约正确后才继续。

---

## 6. 后端开发检查清单

完成 API 实现后，必须满足：

- [ ] `backend/openapi.yaml` 存在且通过 [Swagger Editor](https://editor.swagger.io/) 验证
- [ ] 所有 endpoints 实现与 openapi.yaml 完全一致（路径、方法、参数、响应码）
- [ ] `application.yml` 配置 `springdoc.api-docs.path=/api-docs`
- [ ] JWT 认证在请求头 `Authorization: Bearer <token>` 中提取
- [ ] 所有错误响应符合统一格式 `{ code, message, data }`
- [ ] Contract Test 通过（如果 cloudbuild 集成 dredd）

---

## 7. 前端开发检查清单

完成页面实现后，必须满足：

- [ ] 所有 API 调用使用 `VITE_API_BASE_URL` 环境变量
- [ ] 接口字段与 openapi.yaml 中 `schemas` 定义完全一致
- [ ] 错误处理覆盖所有 HTTP 错误码和业务错误码
- [ ] 分页参数 `page`, `pageSize` 与 openapi.yaml 一致
- [ ] 登录/Token 刷新逻辑符合 openapi.yaml 中的 `expiresIn` 定义
