---
name: full-stack-developer
description: |
  从需求到上线的全栈开发自动化框架。覆盖：需求分析、架构设计、子 Agent 并行开发、GitHub push、Cloud Build 触发器创建（REST API）、自动化部署、监控告警、回滚机制。
  触发场景：新建项目、做一个完整系统、从零到一、帮我开发整个项目、完整流程
  触发短语：新项目、从零开发、做一个全栈项目、帮我开发、完整系统
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
④ GitHub push 触发器创建（REST API，路径过滤）
    ↓
⑤ Cloud Build 自动构建
    ├─ 后端：Maven/Node → Docker → Cloud Run
    └─ 前端：Flutter SDK → Docker(Nginx) → Cloud Run
    ↓
⑥ 测试验证（smoke test）
    ↓
⑦ 配置监控告警（Cloud Monitoring）
    ↓
⑧ 返回链接 + 已知限制
```

> **中断处理**：每个节点完成后记录 `.task-state.json`，中断后从最后一个完成节点继续，不重复工作。
> **回滚机制**：部署失败时自动触发上一版镜像的回滚deploy。

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
      "_DB_HOST": "${_DB_HOST}",
      "_DB_PORT": "${_DB_PORT}",
      "_DB_NAME": "${_DB_NAME}",
      "_DB_USERNAME": "${_DB_USERNAME}"
    }
  }'
```

### 触发器名称规范

| 项目类型 | 触发器名称 | 路径过滤 |
|---------|-----------|---------|
| 后端触发器 | `{project}-github-push` | includes: `backend/**`, excludes: `frontend/**` |
| Flutter 前端触发器 | `{project}-frontend-push` | includes: `frontend/**`, excludes: `backend/**` |
| HTML/JS 前端触发器 | `{project}-frontend-push` | includes: `frontend/**`, excludes: `backend/**` |

> **路径过滤**：必须设置 `pathFilters`，避免后端代码变更触发前端构建，或反之。
> **Substitutions**：`_DB_HOST` 等变量通过 Cloud Build 的 substitution 传递，明文不泄露。

---

## ⑤ cloudbuild.yaml 标准模板

### 前置条件

1. **Secret Manager** 中已创建以下 secret：
   - `DB_PASSWORD`：数据库密码
   - `JWT_SECRET`：JWT 签名密钥

2. **deploy-bot** 已授予以下 IAM 角色：
   - `roles/secretmanager.secretAccessor`（读取 secrets）
   - `roles/run.admin`（部署 Cloud Run）

---

### 后端（Spring Boot + Maven）

```yaml
steps:
  # ① 运行测试
  - name: maven:3.9-eclipse-temurin-17
    id: Test
    entrypoint: mvn
    args: [test, -q]
    dir: backend

  # ② 打包
  - name: maven:3.9-eclipse-temurin-17
    id: Build Package
    entrypoint: mvn
    args: [package, -DskipTests, -q]
    dir: backend
    waitFor: [Test]

  # ③ 构建 Docker 镜像
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

  # ④ 推送镜像
  - name: gcr.io/cloud-builders/docker
    id: Push Image
    args:
      - push
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest
    waitFor: [Build Image]

  # ⑤ 从 Secret Manager 读取密码（不落地磁盘）
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

  # ⑥ 部署（引用 Cloud Build 内置 Secret Manager 支持）
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
  # ① 安装依赖 & 测试
  - name: node:20
    id: Test
    entrypoint: npm
    args: [install, --prefix, backend, &&, npm, test, --prefix, backend]
    dir: .

  # ② 打包（构建产物）
  - name: node:20
    id: Build
    entrypoint: npm
    args: [run, build, --prefix, backend]
    waitFor: [Test]

  # ③ Docker 构建
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

  # ④ 推送
  - name: gcr.io/cloud-builders/docker
    id: Push Image
    args:
      - push
      - asia-east1-docker.pkg.dev/my-project-openclaw-492614/{image-prefix}/{service-name}:latest
    waitFor: [Build Image]

  # ⑤ 部署
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

### 规则

- 迁移文件放在 `backend/src/main/resources/db/migration/`
- 文件命名规范：`V{version}__{description}.sql`（如 `V1__init_users_table.sql`）
- **生产环境迁移**：Cloud Build 部署前通过额外 step 连接数据库执行 Flyway migrate
- **禁止手动修改已执行的迁移文件**，新增需求通过新迁移文件实现

### Cloud Build 集成迁移 step

在 `backend/cloudbuild.yaml` 的 Deploy step 之前添加：

```yaml
  # ⑥ 数据库迁移（部署前）
  - name: gcr.io/cloud-builders/docker
    id: Flyway Migrate
    entrypoint: bash
    args:
      - -c
      - |
        docker run --rm \
          -e FLYWAY_URL=jdbc:mysql://${_DB_HOST}:${_DB_PORT}/${_DB_NAME} \
          -e FLYWAY_USER=${_DB_USERNAME} \
          -e FLYWAY_PASSWORD=$$DB_PASSWORD \
          -v $(pwd)/backend/src/main/resources/db/migration:/flyway/sql \
          flyway/flyway:9 migrate
    secretEnv:
      - DB_PASSWORD
    waitFor: [Push Image]
```

> **fail-fast**：迁移失败则整个 build 失败，不会部署半成品到生产。

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

## ⑨ 监控告警配置（Cloud Monitoring）

### 必做项

部署完成后通过 REST API 创建告警策略：

```bash
# ① 创建通知渠道
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/notificationChannels" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "email",
    "displayName": "{project}-alerts",
    "labels": { "email_address": "{alert-email}" }
  }'

# ② 创建 CPU 使用率 > 80% 告警
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/alertPolicies" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "{project}-high-cpu",
    "conditions": [{
      "displayName": "CPU Usage > 80%",
      "conditionThreshold": {
        "filter": "resource.type=cloud_run_revision AND resource.labels.service_name={service-name}",
        "metric": "run.googleapis.com/container/cpu/utilizations",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.8,
        "duration": "60s"
      }
    }],
    "notificationChannels": ["{channel-id}"]
  }'

# ③ 创建请求错误率 > 1% 告警
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/alertPolicies" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "{project}-high-error-rate",
    "conditions": [{
      "displayName": "Error Rate > 1%",
      "conditionThreshold": {
        "filter": "resource.type=cloud_run_revision AND resource.labels.service_name={service-name}",
        "metric": "run.googleapis.com/request_count",
        "metricFilter": "metric.response_code_class>=500",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.01,
        "duration": "60s"
      }
    }],
    "notificationChannels": ["{channel-id}"]
  }'
```

### 必监控指标

| 指标 | 阈值 | 动作 |
|------|------|------|
| CPU 使用率 | > 80% 持续 1min | 告警 |
| 请求错误率（5xx） | > 1% 持续 1min | 告警 |
| 实例数 | = max-instances | 告警（容量满） |
| 延迟 P99 | > 2s | 告警 |

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

合并到 `develop` 前必须通过：
- `git diff --stat` 检查文件数量异常
- `git log --oneline -5` 检查提交记录
- 单元测试覆盖率 > 70%（Java: JaCoCo, JS: Istanbul）

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
