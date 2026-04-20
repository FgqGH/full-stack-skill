---
name: full-stack-developer
description: |
  从需求到上线的全栈开发自动化框架。覆盖：需求分析、架构设计、子 Agent 并行开发、GitHub push、Cloud Build 触发器创建（REST API）、自动化部署。
  触发场景：新建项目、做一个完整系统、从零到一、帮我开发整个项目、完整流程
  触发短语：新项目、从零开发、做一个全栈项目、帮我开发、完整系统
---

# 全栈开发自动化框架 🚀

## 核心定位

本框架定义了我作为主 Agent 的完整工作流：**强哥说需求 → 我完成所有开发 + 部署 → 返回链接**。

中间所有环节自动执行，强哥零手动操作。

---

## 基础设施配置

### GitHub
- **Owner**: `FgqGH`
- **Token**: `{{GITHUB_TOKEN}}`
- **仓库创建**: 通过 GitHub API `POST /user/repos`
- **代码推送**: `git remote set-url` + `git push`

### GCP
- **Project ID**: `my-project-openclaw-492614`
- **Region**: `asia-east1`
- **Artifact Registry**: `asia-east1-docker.pkg.dev/my-project-openclaw-492614`
- **deploy-bot**: `deploy-bot@my-project-openclaw-492614.iam.gserviceaccount.com`
- **构建触发器创建**: 通过 Cloud Build REST API（CLI 有 bug，必须用 REST）

---

## 完整工作流

```
强哥：提需求
    ↓
① 需求分析 → 输出 SPEC.md
    ↓
② 技术选型
    ├─ 简单信息展示 → HTML/JS + Node.js 后端
    └─ 复杂多角色 → Flutter Web + Spring Boot 后端
    ↓
③ 派 subagent 并行开发
    ├─ 子 Agent A → 后端代码
    └─ 子 Agent B → 前端代码
    ↓
④ GitHub push 触发器创建（REST API）
    ↓
⑤ Cloud Build 自动构建
    ├─ 后端：Maven/Node → Docker → Cloud Run
    └─ 前端：Flutter SDK → Docker(Nginx) → Cloud Run
    ↓
⑥ 验证 → 返回链接
```

---

## ① 需求分析 → SPEC.md

每个项目必须先输出 `SPEC.md`，包含：

### 内容结构

```markdown
# {项目名称} - 项目规格说明书

## 1. 项目概述
- 项目类型：
- 目标用户：
- 核心功能：
- 独特价值：

## 2. 技术架构
- 前端技术栈：
- 后端技术栈：
- 数据库：
- 部署方式：

## 3. 数据库设计
### {表名}
| 字段 | 类型 | 说明 |
|------|------|------|

## 4. API 设计
### 认证
POST /api/auth/login

### {模块}
GET    /api/{resource}     → 列表
POST   /api/{resource}     → 创建
GET    /api/{resource}/{id} → 详情
PUT    /api/{resource}/{id} → 更新
DELETE /api/{resource}/{id} → 删除

## 5. 页面结构
- /login
- /register
- /dashboard
- /admin/...
```

---

## ② 技术选型规则

| 场景 | 前端 | 后端 | 数据库 | 部署 |
|------|------|------|--------|------|
| 快速验证/H5 | HTML/JS | Node.js + Express | Supabase | Cloud Run |
| 多角色/复杂状态 | Flutter Web | Spring Boot | MySQL/Supabase | Cloud Run |
| 内容展示为主 | HTML/JS | Node.js + Express | Supabase | Cloud Run |

---

## ③ 子 Agent 开发规范

### 派发任务模板

```json
{
  "runtime": "subagent",
  "cwd": "/root/.openclaw/workspace/projects/{project-name}",
  "task": """
  请在 {project-path} 下开发 {project-name} 系统后端。
  
  技术要求：{tech-stack}
  数据库连接：host={host}, port={port}, database={db}, user={user}, password={password}
  GitHub Token：{{GITHUB_TOKEN}}
  仓库名：FgqGH/{repo-name}
  
  参考 SPEC.md 内容：
  {spec-content}
  
  请完成：
  1. 项目骨架搭建
  2. 数据库表结构（SQL 文件）
  3. 后端所有 API
  4. Docker 配置（Dockerfile + cloudbuild.yaml）
  5. push 到 GitHub
  """
}
```

### 后端标准结构（Spring Boot）

```
backend/
├── src/main/java/com/{org}/{project}/
│   ├── {project}Application.java
│   ├── config/         # CorsConfig, SecurityConfig
│   ├── controller/     # REST Controller
│   ├── service/impl/   # Service 实现
│   ├── mapper/        # MyBatis Mapper
│   ├── entity/         # 数据库实体
│   ├── dto/            # 数据传输对象
│   ├── security/       # JWT Filter
│   └── common/        # Result 封装、全局异常
├── src/main/resources/
│   ├── application.yml
│   └── db/migration/  # Flyway SQL
├── src/test/java/...
├── pom.xml
├── Dockerfile
└── cloudbuild.yaml
```

### 后端标准结构（Node.js）

```
backend/
├── src/
│   ├── index.ts         # 入口
│   ├── routes/         # 路由
│   ├── services/       # 业务逻辑
│   ├── middleware/      # JWT 认证
│   └── types/          # TypeScript 类型
├── package.json
├── tsconfig.json
├── Dockerfile
└── cloudbuild.yaml
```

### 前端标准结构（Flutter Web）

```
frontend/
├── lib/
│   ├── app/            # main.dart + router
│   ├── models/         # 数据模型
│   ├── providers/      # Riverpod 状态管理
│   ├── screens/        # 页面
│   └── services/       # API 调用
├── pubspec.yaml
├── Dockerfile.nginx     # 前端专用 Nginx Dockerfile
├── nginx.conf
└── cloudbuild.yaml    # Flutter 构建 + Nginx 部署
```

### 前端标准结构（HTML/JS）

```
frontend/
├── index.html
├── admin.html
├── venues.html
├── booking.html
├── my-bookings.html
├── css/
├── js/
└── firebase.json
```

---

## ④ Cloud Build 触发器创建（REST API）

**必须用 REST API，CLI 有 bug 无法创建。**

### 创建触发器

```bash
curl -s -X POST \
  "https://cloudbuild.googleapis.com/v1/projects/my-project-openclaw-492614/locations/global/triggers" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "{trigger-name}",
    "github": {
      "owner": "FgqGH",
      "name": "{repo-name}",
      "push": { "branch": ".*" }
    },
    "serviceAccount": "projects/my-project-openclaw-492614/serviceAccounts/deploy-bot@my-project-openclaw-492614.iam.gserviceaccount.com",
    "filename": "{cloudbuild-yaml-path}"
  }'
```

### 触发器名称规范

| 项目类型 | 触发器名称 |
|---------|-----------|
| 后端触发器 | `{project}-github-push` |
| Flutter 前端触发器 | `{project}-frontend-push` |

---

## ⑤ cloudbuild.yaml 标准模板

### 后端（Spring Boot + Maven）

```yaml
steps:
  - name: maven:3.9-eclipse-temurin-17
    id: Build Package
    entrypoint: mvn
    args: [package, -DskipTests, -q]
    dir: backend

  - name: gcr.io/cloud-builders/docker
    id: Build Image
    args:
      - build
      - -t
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest
      - -f
      - backend/Dockerfile
      - backend

  - name: gcr.io/cloud-builders/docker
    id: Push Image
    args:
      - push
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest
    waitFor: [Build Image]

  - name: gcr.io/google.com/cloudsdktool/cloud-sdk
    id: Deploy
    entrypoint: gcloud
    args:
      - run
      - deploy
      - {service-name}
      - --image=asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest
      - --region=asia-east1
      - --platform=managed
      - --allow-unauthenticated
      - --port=8080
      - --min-instances=1
      - --memory=512Mi
      - --set-env-vars=DB_HOST=$$DB_HOST,DB_PORT=$$DB_PORT,DB_NAME=$$DB_NAME,DB_USERNAME=$$DB_USERNAME,DB_PASSWORD=$$DB_PASSWORD,JWT_SECRET=$$JWT_SECRET
    env:
      - DB_HOST=${_DB_HOST}
      - DB_PORT=${_DB_PORT}
      - DB_NAME=${_DB_NAME}
      - DB_USERNAME=${_DB_USERNAME}
      - DB_PASSWORD=${_DB_PASSWORD}
      - JWT_SECRET=${_JWT_SECRET}
    waitFor: [Push Image]

images:
  - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest

timeout: "600s"
```

### 前端（Flutter Web + Nginx）

```yaml
steps:
  - name: ubuntu:22.04
    entrypoint: bash
    args:
      - -c
      - |
        set -e
        apt-get update -qq && apt-get install -y -qq curl xz-utils git unzip > /dev/null 2>&1
        git clone --depth 1 --branch 3.24.5 https://github.com/flutter/flutter.git /opt/flutter
        export PATH="/opt/flutter/bin:$$PATH"
        flutter config --no-analytics
        flutter precache --web
        cd frontend
        flutter pub get
        flutter build web --dart-define=API_URL=https://{backend-host}/api
    id: Install Flutter & Build
    waitFor: ['-']

  - name: gcr.io/cloud-builders/docker
    args:
      - build
      - -t
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}-frontend:latest
      - -f
      - frontend/Dockerfile.nginx
      - .
    id: Build Docker Image
    waitFor: [Install Flutter & Build]

  - name: gcr.io/cloud-builders/docker
    args:
      - push
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}-frontend:latest
    id: Push Image
    waitFor: [Build Docker Image]

  - name: gcr.io/google.com/cloudsdktool/cloud-sdk
    entrypoint: gcloud
    args:
      - run
      - deploy
      - {service-name}-frontend
      - --image=asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}-frontend:latest
      - --region=asia-east1
      - --platform=managed
      - --allow-unauthenticated
      - --port=8080
      - --min-instances=1
      - --memory=256Mi
    id: Deploy
    waitFor: [Push Image]

images:
  - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}-frontend:latest

timeout: "600s"
```

### 前端 Dockerfile.nginx

```dockerfile
FROM nginx:alpine
COPY frontend/build/web /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
```

### 前端 nginx.conf

```nginx
server {
    listen 8080;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass https://{backend-host}/api/;
        proxy_set_header Host {backend-host};
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;
}
```

---

## ⑥ Cloud Run IAM 权限修复

部署后若返回 403，执行：

```bash
gcloud run services add-iam-policy-binding {service-name} \
  --region=asia-east1 \
  --member=allUsers \
  --role=roles/run.invoker
```

---

## ⑦ 项目交付标准

交付内容：
- 前端访问地址（Cloud Run URL）
- 后端 API 地址
- 管理员账号密码
- 核心 API 测试结果
- 已知限制（如缺少外部配置）

---

## 断点续接

每个项目在 `~/.openclaw/workspace/projects/{project}/.task-state.json` 记录进度：

```json
{
  "spec": "done",
  "backend": "in-progress",
  "frontend": "pending",
  "triggers": "pending",
  "deployed": false
}
```

中断后从最后一个完成节点继续，不重复工作。
