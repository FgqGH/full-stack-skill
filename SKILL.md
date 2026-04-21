---
name: full-stack-developer
description: |
  从需求到上线的全栈开发自动化框架。覆盖：需求分析、架构设计、子 Agent 并行开发、GitHub push、Cloud Build 触发器创建（REST API）、自动化部署、监控告警、回滚机制。
  触发场景：新建项目、做一个完整系统、从零到一、帮我开发整个项目、完整流程
  触发短语：新项目、从零开发、做一个全栈项目、帮我开发、完整系统
tags:
  - fullstack
  - gcp
  - cloud-run
  - cloud-build
  - flutter
  - spring-boot
  - nodejs
  - observability
  - ci-cd
related_skills:
  - github-pr-workflow
  - cloud-run-deploy
  - database-migration
  - monitoring
usage_hint: |
  当用户说"新项目"、"从零开发"、"做一个完整系统"、"帮我开发"、"完整流程"时触发本技能。
  完整流程：需求分析(SPEC.md) → 技术选型 → 并行开发(前端+后端subagent) → GitHub push
    → 创建触发器(REST API) → Cloud Build 构建 → 部署 Cloud Run → Smoke Test
    → 配置监控告警(OTel+Cloud Monitoring) → 返回访问链接。
---

# 全栈开发自动化框架 🚀

## 核心定位

本框架定义了我作为主 Agent 的完整工作流：**强哥说需求 → 我完成所有开发 + 部署 → 返回链接**。

中间所有环节自动执行，强哥零手动操作。

> **安全原则**：所有 secrets（密码、JWT_SECRET、API_KEY）必须通过 GCP Secret Manager 管理，严禁写入 cloudbuild.yaml 的 env 字段或日志。

---

## 基础设施配置

### GitHub
- **Owner**: `FgqGH`
- **Token**: `{{GITHUB_TOKEN}}`
- **仓库创建**: 通过 GitHub API `POST /user/repos`
- **代码推送**: `git remote set-url` + `git push`
- **触发器脚本**: `references/create-trigger.sh`

### GCP
- **Project ID**: `my-project-openclaw-492614`
- **Region**: `asia-east1`
- **Artifact Registry**: `asia-east1-docker.pkg.dev/my-project-openclaw-492614`
- **deploy-bot**: `deploy-bot@my-project-openclaw-492614.iam.gserviceaccount.com`
- **构建触发器创建**: 通过 Cloud Build REST API（CLI 有 bug，必须用 REST）
- **环境初始化**: `scripts/gcp-init.sh`（首次使用前运行一次）

---

## 完整工作流

```
强哥：提需求
    ↓
① 需求分析 → 输出 SPEC.md + openapi.yaml
    ↓
② 技术选型
    ├─ 简单信息展示 → HTML/JS + Node.js 后端
    └─ 复杂多角色 → Flutter Web + Spring Boot 后端
    ↓
③ 派 subagent 并行开发
    ├─ 子 Agent A → 后端代码 + 单元测试 + 集成测试
    └─ 子 Agent B → 前端代码 + Widget Test + Integration Test
    ↓
④ GitHub push 触发器创建（REST API，路径过滤）
    ↓
⑤ Cloud Build 自动构建
    ├─ 后端：Contract Test → Maven/Node 测试（含覆盖率）→ Docker → Cloud Run
    └─ 前端：Flutter Build → Widget Test → Lighthouse CI → Docker → Cloud Run
    ↓
⑥ Smoke Test（失败自动 rollback）
    ↓
⑦ 配置监控告警（Cloud Monitoring + OTel 可观测性）
    ├─ 结构化日志（JSON + correlationId）
    ├─ OpenTelemetry 追踪集成
    ├─ 告警策略（CPU/错误率/延迟/SLO）
    ├─ Dashboard 大盘
    └─ 告警自愈（Smoke Test → Auto Rollback）
    ↓
⑧ 返回链接 + 已知限制
```

> **中断处理**：每个节点完成后记录 `.task-state.json`，中断后从最后一个完成节点继续，不重复工作。
> **回滚机制**：部署失败时自动触发上一版镜像的回滚deploy。

---

## ① 需求分析 → SPEC.md + openapi.yaml

每个项目必须先输出 `SPEC.md` 和 `openapi.yaml`（契约优先）：

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
├── openapi.yaml        # OpenAPI 3.0 契约定义
├── dredd.yml           # Contract Test 配置
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
├── openapi.yaml        # OpenAPI 3.0 契约定义
├── dredd.yml           # Contract Test 配置
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

> **推荐使用 `references/create-trigger.sh` 脚本**，自动处理 REST API 调用和参数构造，幂等设计。
> ```bash
> chmod +x references/create-trigger.sh
> # 后端触发器
> ./references/create-trigger.sh backend <project-name> FgqGH <repo-name>
> # 前端触发器
> ./references/create-trigger.sh frontend <project-name> FgqGH <repo-name>
> ```

### 手动 REST API（仅参考）

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
      "push": {
        "branch": ".*",
        "pathFilters": {
          "includes": ["{include-path}"],
          "excludes": ["{exclude-path}"]
        }
      }
    },
    "serviceAccount": "projects/my-project-openclaw-492614/serviceAccounts/deploy-bot@my-project-openclaw-492614.iam.gserviceaccount.com",
    "filename": "{cloudbuild-yaml-path}",
    "substitutions": {
      "_PROJECT_NAME": "{project-name}",
      "_REGION": "asia-east1",
      "_AR_REPO": "asia-east1-docker.pkg.dev/my-project-openclaw-492614",
      "_IMAGE_PREFIX": "{project-name}",
      "_SERVICE_NAME": "{service-name}",
      "_DB_HOST": "${_DB_HOST}",
      "_DB_PORT": "${_DB_PORT}",
      "_DB_NAME": "${_DB_NAME}",
      "_DB_USERNAME": "${_DB_USERNAME}"
    }
  }'
```

### 触发器名称规范

| 项目类型 | 触发器名称 | 路径过滤 | cloudbuild.yaml |
|---------|-----------|---------|----------------|
| 后端触发器 | `{project}-backend-push` | includes: `backend/**`, excludes: `frontend/**` | `backend/cloudbuild.yaml` |
| Flutter 前端触发器 | `{project}-frontend-push` | includes: `frontend/**`, excludes: `backend/**` | `frontend/cloudbuild.yaml` |
| HTML/JS 前端触发器 | `{project}-frontend-push` | includes: `frontend/**`, excludes: `backend/**` | `frontend/cloudbuild.yaml` |

> **路径过滤**：必须设置 `pathFilters`，避免后端代码变更触发前端构建，或反之。
> **Substitutions**：`_DB_HOST` 等变量通过 Cloud Build substitution 传递（实际值来自 gcp-init.sh 创建的 Cloud SQL 实例）。
> **注意**：必须用 REST API 创建触发器，CLI 有 bug 无法创建。
> **自动化脚本**：`scripts/gcp-init.sh` 用于初始化基础环境，`references/create-trigger.sh` 用于自动化创建触发器。

---

## ⑤ cloudbuild.yaml 标准模板

### 前置条件（环境初始化）

> **推荐使用自动化脚本**：首次部署前运行一次 `scripts/gcp-init.sh` 即可完成所有初始化，幂等设计，重复运行安全。
> ```bash
> chmod +x scripts/gcp-init.sh
> ./scripts/gcp-init.sh my-project-openclaw-492614
> ```

手动步骤（供参考，不推荐逐条执行）：
1. **启用 GCP API**：
   ```bash
   gcloud services enable secretmanager.googleapis.com run.googleapis.com \
     cloudbuild.googleapis.com sqladmin.googleapis.com monitoring.googleapis.com \
     artifactregistry.googleapis.com --project=my-project-openclaw-492614
   ```

2. **创建 Service Account**：
   ```bash
   gcloud iam service-accounts create deploy-bot \
     --display-name="Deploy Bot for CI/CD" --project=my-project-openclaw-492614
   ```

3. **授予 IAM 角色**（deploy-bot 需要）：
   - `roles/artifactregistry.admin`
   - `roles/run.admin`
   - `roles/cloudsql.admin`
   - `roles/storage.objectAdmin`
   - `roles/secretmanager.secretAccessor`
   - `roles/monitoring.admin`
   - `roles/logging.admin`

4. **创建 Secrets**（JWT_SECRET / DB_PASSWORD）并授予 deploy-bot secretAccessor 权限：
   ```bash
   # 创建 secrets
   echo -n "$(openssl rand -base64 32)" | gcloud secrets create JWT_SECRET --data-file=- --project=my-project-openclaw-492614
   echo -n "$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)" | gcloud secrets create DB_PASSWORD --data-file=- --project=my-project-openclaw-492614
   # 授权
   gcloud secrets add-iam-policy-binding JWT_SECRET --member=serviceAccount:deploy-bot@my-project-openclaw-492614.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor --project=my-project-openclaw-492614
   gcloud secrets add-iam-policy-binding DB_PASSWORD --member=serviceAccount:deploy-bot@my-project-openclaw-492614.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor --project=my-project-openclaw-492614
   ```

5. **配置 Artifact Registry**：
   ```bash
   gcloud artifacts repositories create asia-east1-docker-repo \
     --repository-format=docker --location=asia-east1 --project=my-project-openclaw-492614
   gcloud auth configure-docker asia-east1-docker.pkg.dev --quiet
   ```

> **踩坑记录**：IAM 角色已配不代表 API 可用——Secret Manager API 必须先在 GCP Console 或通过 `gcloud services enable` 启用，否则报 `API has not been used ... or it is disabled`。

---

### 后端（Spring Boot + Maven）

```yaml
steps:
  # 0. 启动 Mock Server（使用 prism）
  - name: node:20
    id: Start Mock Server
    entrypoint: npx
    args:
      - "@stoplight/prism"
      - "mock"
      - backend/openapi.yaml
      - "--port"
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
      - "--config"
      - backend/dredd.yml
    waitFor: [Start Mock Server]

  # 2. 运行单元测试
  - name: maven:3.9-eclipse-temurin-17
    id: Test
    entrypoint: mvn
    args: [test, -q]
    dir: backend
    waitFor: [Contract Test]

  # 3. 打包
  - name: maven:3.9-eclipse-temurin-17
    id: Build Package
    entrypoint: mvn
    args: [package, -DskipTests, -q]
    dir: backend
    waitFor: [Test]

  # 4. 构建 Docker 镜像
  - name: gcr.io/cloud-builders/docker
    id: Build Image
    args:
      - build
      - -t
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest
      - -f
      - backend/Dockerfile
      - backend
    waitFor: [Build Package]

  # 5. 推送镜像
  - name: gcr.io/cloud-builders/docker
    id: Push Image
    args:
      - push
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest
    waitFor: [Build Image]

  # 6. 从 Secret Manager 读取密码（不落地磁盘）
  - name: gcr.io/google.com/cloudsdktool/cloud-sdk
    id: Read Secrets
    entrypoint: bash
    args:
      - -c
      - |
        echo "DB_PASSWORD=$$(gcloud secrets versions access latest --secret=DB_PASSWORD --project=my-project-openclaw-492614)" > /envvars.txt
        echo "JWT_SECRET=$$(gcloud secrets versions access latest --secret=JWT_SECRET --project=my-project-openclaw-492614)" >> /envvars.txt
    env:
      - CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=/credential.json
    secretEnv:
      - DB_PASSWORD
      - JWT_SECRET
    waitFor: [Push Image]

  # 7. 部署（引用 Cloud Build 内置 Secret Manager 支持）
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
      - --max-instances=10
      - --concurrency=80
      - --memory=512Mi
      - --set-env-vars=DB_HOST=${_DB_HOST},DB_PORT=${_DB_PORT},DB_NAME=${_DB_NAME},DB_USERNAME=${_DB_USERNAME}
    secretEnv:
      - DB_PASSWORD
      - JWT_SECRET
    waitFor: [Read Secrets]

images:
  - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest

timeout: "600s"
availableSecrets:
  secretManager:
    - versionName: projects/my-project-openclaw-492614/secrets/DB_PASSWORD/versions/latest
      env: DB_PASSWORD
    - versionName: projects/my-project-openclaw-492614/secrets/JWT_SECRET/versions/latest
      env: JWT_SECRET
```

> **cost control**：`--max-instances=10 --concurrency=80` 防止流量突增爆预算。
> **secretEnv**：密码通过 Cloud Build 内置的 `availableSecrets.secretManager` 注入，从不落地磁盘，不进日志。
> **测试**：移除了 `-DskipTests`，CI 必须跑测试通过才能继续。

---

### 后端（Node.js + Express）

```yaml
steps:
  # 0. 启动 Mock Server（使用 prism）
  - name: node:20
    id: Start Mock Server
    entrypoint: npx
    args:
      - "@stoplight/prism"
      - "mock"
      - backend/openapi.yaml
      - "--port"
      - "4010"
    background: true
    waitFor: ["-"]

  # 1. 运行 Contract Test
  - name: node:20
    id: Contract Test
    entrypoint: npx
    args:
      - dredd
      - backend/openapi.yaml
      - http://localhost:4010
      - "--config"
      - backend/dredd.yml
    waitFor: [Start Mock Server]

  # 2. 安装依赖 & 单元测试
  - name: node:20
    id: Test
    entrypoint: npm
    args: [install, --prefix, backend, &&, npm, test, --prefix, backend]
    dir: .
    waitFor: [Contract Test]

  # 3. 打包（构建产物）
  - name: node:20
    id: Build
    entrypoint: npm
    args: [run, build, --prefix, backend]
    waitFor: [Test]

  # 4. Docker 构建
  - name: gcr.io/cloud-builders/docker
    id: Build Image
    args:
      - build
      - -t
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest
      - -f
      - backend/Dockerfile
      - backend
    waitFor: [Build]

  # 5. 推送
  - name: gcr.io/cloud-builders/docker
    id: Push Image
    args:
      - push
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest
    waitFor: [Build Image]

  # 6. 部署
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
      - --max-instances=10
      - --concurrency=80
      - --memory=512Mi
      - --set-env-vars=DB_HOST=${_DB_HOST},DB_PORT=${_DB_PORT},DB_NAME=${_DB_NAME},DB_USERNAME=${_DB_USERNAME}
    secretEnv:
      - DB_PASSWORD
    waitFor: [Push Image]

images:
  - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest

timeout: "600s"
availableSecrets:
  secretManager:
    - versionName: projects/my-project-openclaw-492614/secrets/DB_PASSWORD/versions/latest
      env: DB_PASSWORD
```

### 前端（Flutter Web + Nginx）

```yaml
steps:
  # ① 安装 Flutter & 构建（并行）
  - name: ubuntu:22.04
    entrypoint: bash
    args:
      - -c
      - |
        set -e
        apt-get update -qq && apt-get install -y -qq curl xz-utils git unzip > /dev/null 2>&1
        git clone --depth 1 --branch 3.24.5 https://github.com/flutter/flutter.git /opt/flutter
        export PATH="/opt/flutter/bin:$PATH"
        flutter config --no-analytics
        flutter precache --web
        cd frontend
        flutter pub get
        flutter build web --dart-define=API_URL=https://{backend-host}/api
    id: Install Flutter & Build
    waitFor: ['-']

  # ② Docker 构建
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

  # ③ 推送
  - name: gcr.io/cloud-builders/docker
    args:
      - push
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}-frontend:latest
    id: Push Image
    waitFor: [Build Docker Image]

  # ④ 部署
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
      - --max-instances=5
      - --concurrency=100
      - --memory=256Mi
    id: Deploy
    waitFor: [Push Image]

images:
  - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}-frontend:latest

timeout: "600s"
```

> **cost control**：`--max-instances=5 --concurrency=100`，前端资源需求低于后端。

---

### 前端（HTML/JS + Nginx）

```yaml
steps:
  # ① 简单构建（压缩）
  - name: ubuntu:22.04
    entrypoint: bash
    args:
      - -c
      - |
        apt-get update -qq && apt-get install -y -qq nginx > /dev/null 2>&1
        # 如果有 JS 构建步骤在这里
    id: Build
    waitFor: ['-']

  # ② Docker 构建
  - name: gcr.io/cloud-builders/docker
    id: Build Image
    args:
      - build
      - -t
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}-frontend:latest
      - -f
      - frontend/Dockerfile.nginx
      - .
    waitFor: [Build]

  # ③ 推送 & 部署（合并减少步骤）
  - name: gcr.io/cloud-builders/docker
    id: Push Image
    args:
      - push
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}-frontend:latest
    waitFor: [Build Image]

  - name: gcr.io/google.com/cloudsdktool/cloud-sdk
    id: Deploy
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
      - --max-instances=5
      - --concurrency=100
      - --memory=128Mi
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
        # Cloud Run 默认 HTTP，不是 HTTPS
        proxy_pass http://{backend-host}/api/;
        proxy_set_header Host {backend-host};
        proxy_hide_header X-Frame-Options;
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;
}
```

> **注意**：`proxy_pass` 用 `http://` 而非 `https://`，Cloud Run 服务间通信默认是 HTTP。

---

## ⑥ 数据库迁移（Flyway）

> **参考文档**：`references/database-migration.md` — 包含完整 Flyway 配置、幂等写法、UNDO rollback、多环境策略、常见错误处理。

### 规则

- 迁移文件放在 `backend/src/main/resources/db/migration/`（Spring Boot）或 `backend/migrations/`（Node.js）
- 文件命名规范：`V{version}__{description}.sql`（如 `V1__init_users_table.sql`）
- **生产环境迁移**：Cloud Build 部署前通过 Flyway migrate 执行
- **禁止手动修改已执行的迁移文件**，新增需求通过新的 migration 文件实现
- `clean-disabled: true`（生产禁止 clean）
- 大表数据迁移必须分批（每批 ≤ 10000 行）

### Cloud Build 迁移 Step（增强版，含失败 Rollback）

在 `backend/cloudbuild.yaml` 的 Deploy step **之前**添加：

```yaml
  # ⑥ 数据库迁移（部署前，失败自动回滚镜像）
  - name: gcr.io/cloud-builders/docker
    id: Flyway Migrate
    entrypoint: bash
    args:
      - -c
      - |
        set -e
        echo "Running Flyway migration..."
        docker run --rm \
          -e FLYWAY_URL="jdbc:mysql://${_DB_HOST}:${_DB_PORT}/${_DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true" \
          -e FLYWAY_USER=${_DB_USERNAME} \
          -e FLYWAY_PASSWORD=$$DB_PASSWORD \
          -v $(pwd)/backend/src/main/resources/db/migration:/flyway/sql \
          flyway/flyway:9 migrate || {
          echo "ERROR: Flyway migration failed, rolling back image..."
          gcloud run services update-traffic ${SERVICE_NAME} \
            --region=asia-east1 --to-latest --platform=managed 2>&1 || true
          exit 1
        }
        echo "Migration completed successfully"
    secretEnv:
      - DB_PASSWORD
    env:
      - CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=/credential.json
    waitFor: [Push Image]

  # ⑥b Schema 版本验证
  - name: gcr.io/cloud-builders/docker
    id: Validate Schema
    entrypoint: bash
    args:
      - -c
      - |
        docker run --rm \
          -e FLYWAY_URL="jdbc:mysql://${_DB_HOST}:${_DB_PORT}/${_DB_NAME}?useSSL=false" \
          -e FLYWAY_USER=${_DB_USERNAME} \
          -e FLYWAY_PASSWORD=$$DB_PASSWORD \
          flyway/flyway:9 info
    secretEnv:
      - DB_PASSWORD
    waitFor: [Flyway Migrate]
```

> **fail-fast**：迁移失败则整个 build 失败并回滚镜像，不会部署半成品到生产。

---

## ⑦ 回滚机制

### 自动回滚触发条件

- Cloud Build 部署 step 返回非 0
- 部署后 smoke test 检测到 5xx 错误

### 回滚步骤

```bash
# ① 获取上一版稳定镜像 tag
PREVIOUS_IMAGE=$(gcloud run services describe {service-name} \
  --region=asia-east1 \
  --format="value(status.traffic.targets[0].imageOverride)")

# ② 回滚到上一版
gcloud run services update-traffic {service-name} \
  --region=asia-east1 \
  --to-latest

# ③ 通知
echo "Rollback triggered for {service-name}" >&2
```

### Cloud Build 回滚 step（追加到 cloudbuild.yaml）

```yaml
  # ⑦ 部署后 smoke test
  - name: curlimages/curl
    id: Smoke Test
    entrypoint: bash
    args:
      - -c
      - |
        set -e
        sleep 10
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://{service-url})
        if [ "$HTTP_CODE" -ge 500 ]; then
          echo "Smoke test failed with $HTTP_CODE, rolling back..."
          gcloud run services update-traffic {service-name} --region=asia-east1 --to-latest
          exit 1
        fi
        echo "Smoke test passed: $HTTP_CODE"
    waitFor: [Deploy]
```

---

## ⑧ Cloud Run IAM 权限修复

部署后若返回 403，执行：

```bash
gcloud run services add-iam-policy-binding {service-name} \
  --region=asia-east1 \
  --member=allUsers \
  --role=roles/run.invoker
```

---

## ⑨ 监控告警配置（Cloud Monitoring + OTel 可观测性）

> **参考文档**：`references/observability.md` — 包含完整的结构化日志规范、OTel 追踪配置、告警自愈机制、运维 Runbook 和 SLO 定义。下文为快速执行参考，完整规范见 reference 文档。

### 必做清单（部署后立即执行）

1. 创建通知渠道（Email）
2. 创建 4 个告警策略：CPU > 80%、错误率 > 1%、延迟 P99 > 2s、内存 > 85%
3. 配置 Smoke Test + Auto Rollback（cloudbuild.yaml 追加 step）
4. 创建 Cloud Monitoring Dashboard
5. 验证告警能收到邮件

### 核心指标

| 指标 | 阈值 | 持续时间 | 级别 | 动作 |
|------|------|---------|------|------|
| CPU 使用率 | > 80% | 1min | WARNING | 通知 |
| CPU 使用率 | > 95% | 1min | CRITICAL | 自动扩容 |
| 5xx 错误率 | > 1% | 2min | WARNING | 通知 |
| 5xx 错误率 | > 5% | 1min | CRITICAL | 自动回滚 |
| 延迟 P99 | > 2s | 2min | WARNING | 通知 |
| 内存使用率 | > 85% | 3min | WARNING | 通知 |

### 结构化日志（所有服务必须）

JSON 格式，包含字段：`timestamp`、`level`、`message`、`correlationId`、`service`、`traceId`、`spanId`、`userId`、`duration`。

**禁止记录**：`password`、`token`、`secret`、`authorization`、`creditCard`。

### OpenTelemetry 追踪集成

所有后端服务必须集成 OTel SDK，自动生成 traceId/spanId 并注入到日志。

### Smoke Test + Auto Rollback Step

在 cloudbuild.yaml Deploy step **之后**追加：

```yaml
  # Smoke Test + Auto Rollback
  - name: curlimages/curl
    id: Smoke Test
    entrypoint: bash
    args:
      - -c
      - |
        set -e
        SMOKE_URL="${SERVICE_URL}"
        echo "Waiting 15s for service to be ready..."
        sleep 15
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$${SMOKE_URL}/health" --max-time 30)
        echo "Health check returned: $${HTTP_CODE}"
        if [ "$${HTTP_CODE}" -ge 500 ]; then
          echo "ERROR: Health check failed, triggering rollback..."
          gcloud run services update-traffic ${SERVICE_NAME} --region=asia-east1 --to-latest --platform=managed 2>&1
          exit 1
        fi
        echo "Smoke test passed"
    env:
      - CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=/credential.json
    waitFor: [Deploy]
```

### 告警配置（REST API）

**通知渠道**：
```bash
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/notificationChannels" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "email",
    "displayName": "${PROJECT}-ops-email",
    "labels": { "email_address": "${ALERT_EMAIL}" }
  }'
```

**CPU > 80% 告警**：
```bash
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/alertPolicies" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "${PROJECT}-cpu-high",
    "combiner": "OR",
    "conditions": [{
      "displayName": "CPU > 80%",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE_NAME}\"",
        "metric": "run.googleapis.com/container/cpu/utilizations",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.8,
        "duration": "60s"
      }
    }],
    "notificationChannels": ["${NOTIFICATION_CHANNEL}"]
  }'
```

### Cloud Monitoring Dashboard（可选但推荐）

```bash
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/dashboards" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "${PROJECT}-Dashboard",
    "gridLayout": { "columns": 2, "widgets": [
      { "title": "RPM", "xyChart": { "dataSets": [{ "timeSeriesQuery": { "timeSeriesFilter": { "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE_NAME}\"", "metric": "run.googleapis.com/request_count" } } }] } },
      { "title": "Error Rate", "xyChart": { "dataSets": [{ "timeSeriesQuery": { "timeSeriesFilter": { "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE_NAME}\" AND metric.labels.response_code_class=\"500\"", "metric": "run.googleapis.com/request_count" } } }] } },
      { "title": "CPU %", "xyChart": { "dataSets": [{ "timeSeriesQuery": { "timeSeriesFilter": { "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE_NAME}\"", "metric": "run.googleapis.com/container/cpu/utilizations" } } }] } },
      { "title": "Latency P99", "xyChart": { "dataSets": [{ "timeSeriesQuery": { "timeSeriesFilter": { "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE_NAME}\"", "metric": "run.googleapis.com/request_latencies" }, "secondaryAggregation": { "aggregation": { "reducer": "REDUCE_PERCENTILE", "percentile": 99 } } } }] } }
    ]}
  }'
```

### SLO 定义（每个服务必须）

| SLO | 目标 | 告警阈值 |
|-----|------|---------|
| 可用性 | 99.9% | < 99.5% |
| 延迟 P99 | < 500ms | > 1s |
| 错误率 | < 0.1% | > 0.5% |

### 运维 Runbook（快速查）

| 告警 | 排查命令 | 常见原因 | 临时缓解 |
|------|---------|---------|---------|
| CPU 高 | Cloud Console → Metrics | 死循环/频繁GC/连接池耗尽 | `--max-instances=5` |
| 延迟 P99 高 | OTel Trace → 最慢 span | 慢查询/第三方API超时 | 检查数据库索引 |
| 错误率升高 | Cloud Logging → `severity=ERROR` | 新部署问题/外部依赖故障 | 回滚 |
| 实例数满 | `gcloud run services describe` | 流量突增/爬虫 | 临时提 max-instances |

---

## ⑩ Subagent 协作规范

### 分支策略

- 后端：`feature/backend-{module}` → `develop` → `main`
- 前端：`feature/frontend-{module}` → `develop` → `main`
- 禁止直接 push 到 `main`，必须通过 PR

### 冲突处理

1. Subagent 完成模块后，提交 PR 到 `develop`
2. 主 Agent 合并前检查冲突，若有冲突则：
   - 保留双方核心逻辑
   - 合并配置/常量
   - 标注 `<<<<<<< CONFLICT` 供人工确认
3. 人工确认后主 Agent 完成合并

### 代码质量门禁

合并到 `develop` 前必须通过所有质量检查：

- [ ] Contract Test 通过（100% API 路径覆盖）
- [ ] 单元测试通过（`mvn test` / `npm test` / `flutter test`）
- [ ] 覆盖率达标（后端 line > 70%，前端 widget test > 50%）
- [ ] Lighthouse CI Performance > 90（前端子项目）
- [ ] 没有 `console.error` / 未捕获异常
- [ ] 没有硬编码的 secrets 或测试数据
- [ ] `git diff --stat` 文件数量正常（排除 node_modules 等）

---

## ⑪ 项目交付标准

交付内容：
- 前端访问地址（Cloud Run URL）
- 后端 API 地址
- 管理员账号密码（初始密码需强制更换）
- 核心 API 测试结果（curl 测试截图）
- 告警配置确认（已创建哪些告警策略）
- 已知限制（如缺少外部配置、第三方依赖）
- GitHub 仓库地址 + 分支策略说明

---

## 断点续接

每个项目在 `~/.openclaw/workspace/projects/{project}/.task-state.json` 记录进度：

```json
{
  "spec": "done",
  "backend": "done",
  "frontend": "done",
  "triggers": "done",
  "migration": "done",
  "monitoring": "done",
  "deployed": true,
  "frontend_url": "https://...",
  "backend_url": "https://...",
  "deployed_at": "2024-04-21T08:30:00Z"
}
```

中断后从最后一个完成节点继续，不重复工作。
