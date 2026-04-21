# 数据库迁移可靠性：Flyway + 失败自动 Rollback

## 核心原则

**迁移失败 = 部署阻断，绝不让半成品数据库进入生产。** Flyway 是数据库版本控制的唯一来源，禁止手动修改已执行的迁移文件。

---

## 1. Flyway 迁移规范

### 文件命名规范

```
V{version}__{description}.sql
V1__init_users_table.sql
V2__add_booking_table.sql
V3__add_index_on_users_email.sql
```

- `version`：纯数字，递增（1, 2, 3... 或 1.0, 1.1...）
- `description`：下划线分隔，描述迁移内容
- **禁止修改已执行过的迁移文件**（Flyway 会检测 checksum，修改会导致 migration 失败）

### 迁移文件存放位置

| 后端类型 | 路径 |
|---------|------|
| Spring Boot | `backend/src/main/resources/db/migration/` |
| Node.js | `backend/migrations/` |

### 基线迁移（已有数据库）

如果数据库已有表结构，从当前状态创建基线：

```bash
# 为已有数据库创建基线（不执行任何迁移）
flyway -url=jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME} \
       -user=${DB_USER} -password=${DB_PASSWORD} \
       baseline
```

### 生产环境迁移原则

1. **先在本地/Dev 环境测试**：所有迁移必须先在 dev 环境验证
2. **幂等迁移**：优先使用 `CREATE TABLE IF NOT EXISTS`、`ALTER TABLE ... ADD COLUMN IF NOT EXISTS`（MySQL 语法需用存储过程或子查询实现）
3. **最小权限**：Flyway 连接使用专用的 `flyway_user`（仅 DDL 权限）
4. **大事务拆分**：单个迁移文件不超过 10MB，超大表用分批次 `INSERT INTO ... SELECT` 迁移

---

## 2. Spring Boot + Flyway 配置

### 依赖 (`pom.xml`)

```xml
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-core</artifactId>
    <version>9.22.3</version>
</dependency>
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-mysql</artifactId>
    <version>9.22.3</version>
</dependency>
```

### 配置 (`application.yml`)

```yaml
spring:
  flyway:
    enabled: true
    baseline-on-migrate: true          # 已有数据库允许基线
    baseline-version: 0
    locations: classpath:db/migration
    sql-migration-prefix: V
    sql-migration-separator: __
    sql-migration-suffixes: .sql
    validate-on-migrate: true
    clean-disabled: true                # 生产环境禁止 clean
    connect-retries: 3
    connect-retries-interval: 10
```

### 执行时机

Cloud Build 中，**打包之后、部署之前**执行 Flyway migrate：

```yaml
# cloudbuild.yaml — Flyway step（部署前）
- name: gcr.io/cloud-builders/docker
  id: Flyway Migrate
  entrypoint: bash
  args:
    - -c
    - |
      docker run --rm \
        -e FLYWAY_URL="jdbc:mysql://${_DB_HOST}:${_DB_PORT}/${_DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true" \
        -e FLYWAY_USER=${_DB_USERNAME} \
        -e FLYWAY_PASSWORD=$$DB_PASSWORD \
        -v $(pwd)/backend/src/main/resources/db/migration:/flyway/sql \
        flyway/flyway:9 migrate
  secretEnv:
    - DB_PASSWORD
  waitFor: [Push Image]
```

---

## 3. Node.js + Flyway 配置

### 依赖

```bash
npm install --save-dev flyway
```

### package.json scripts

```json
{
  "scripts": {
    "db:migrate": "flyway -url=$DB_URL -user=$DB_USER -password=$DB_PASSWORD migrate",
    "db:rollback": "flyway -url=$DB_URL -user=$DB_USER -password=$DB_PASSWORD undo"
  }
}
```

### Flyway 配置 (`flyway.conf`)

```properties
flyway.url=jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}
flyway.user=${DB_USERNAME}
flyway.password=${DB_PASSWORD}
flyway.locations=filesystem:./migrations
flyway.baseline-on-migrate=true
flyway.clean-disabled=true
```

---

## 4. 迁移失败自动 Rollback

### Rollback 触发条件

以下情况自动执行回滚：

| 场景 | 判断方式 | 动作 |
|------|---------|------|
| Flyway migrate 失败（exit code ≠ 0） | Cloud Build step 返回非0 | **整个 build 失败，不部署** |
| 部署后 smoke test 检测到 DB 连接错误 | HTTP 500 + `SQLException` 关键字 | 自动回滚到上一镜像 |
| 迁移后 DB schema 与应用期望不符 | Schema metadata 对比 | 告警，人工介入 |

### Cloud Build Rollback Step（追加到 cloudbuild.yaml）

```yaml
# Flyway Migration with Auto-Rollback on Failure
- name: gcr.io/cloud-builders/docker
  id: Flyway Migrate
  entrypoint: bash
  args:
    - -c
    - |
      set -e
      echo "Running Flyway migration..."
      MIGRATION_OUTPUT=$(docker run --rm \
        -e FLYWAY_URL="jdbc:mysql://${_DB_HOST}:${_DB_PORT}/${_DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true" \
        -e FLYWAY_USER=${_DB_USERNAME} \
        -e FLYWAY_PASSWORD=$$DB_PASSWORD \
        -v $(pwd)/backend/src/main/resources/db/migration:/flyway/sql \
        flyway/flyway:9 migrate 2>&1) || {
        echo "ERROR: Flyway migration failed!"
        echo "$$MIGRATION_OUTPUT"
        echo "Triggering image rollback..."
        gcloud run services update-traffic ${SERVICE_NAME} \
          --region=asia-east1 \
          --to-latest \
          --platform=managed 2>&1 || true
        echo "Build failed due to migration error. Deployment rolled back."
        exit 1
      }
      echo "Migration successful:"
      echo "$$MIGRATION_OUTPUT"
  secretEnv:
    - DB_PASSWORD
  env:
    - CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=/credential.json
  waitFor: [Push Image]
```

### Flyway UNDO（推荐生产配置）

对于关键表结构变更，推荐使用 Flyway UNDO：

```bash
# UNDO 上一条 migration（仅限 dev/preview 环境）
flyway -url=jdbc:mysql://... undo
```

> **注意**：Flyway UNDO 需要 `flyway.undo` 收费版（从 Flyway 10 起），或使用免费的 `V{version}__undo_{description}.sql` 手动回滚脚本。

---

## 5. 幂等迁移最佳实践

### MySQL 幂等写法

**添加列**（如果列已存在不报错）：
```sql
-- 方法1：子查询判断（MySQL 8.0+）
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);

-- 方法2：存储过程封装
DELIMITER $$
CREATE PROCEDURE add_column_if_not_exists(
    IN table_name VARCHAR(255),
    IN column_name VARCHAR(255),
    IN column_definition VARCHAR(255)
)
BEGIN
    DECLARE column_exists INT DEFAULT 0;
    SELECT COUNT(*) INTO column_exists
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = table_name
      AND column_name = column_name;

    IF column_exists = 0 THEN
        SET @sql = CONCAT('ALTER TABLE ', table_name, ' ADD COLUMN ', column_name, ' ', column_definition);
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END$$
DELIMITER ;

CALL add_column_if_not_exists('users', 'phone', 'VARCHAR(20)');
```

**添加索引**（如果索引已存在不报错）：
```sql
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
```

**创建表**（如果表已存在不报错）：
```sql
CREATE TABLE IF NOT EXISTS bookings (...);
```

### 数据迁移（大批量）

```sql
-- 大表数据迁移：分批处理，避免锁表
INSERT INTO new_users (id, name, email, created_at)
SELECT id, name, email, created_at FROM old_users
WHERE id > (SELECT MAX(id) FROM new_users)
ORDER BY id
LIMIT 1000;

-- 循环执行直到 old_users 无数据
```

---

## 6. Schema 版本验证（部署前检查）

在部署前验证数据库 schema 与应用期望一致：

```yaml
# cloudbuild.yaml — Schema Validation Step
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

---

## 7. 多环境迁移策略

| 环境 | 基线策略 | UNDO | 备注 |
|------|---------|------|------|
| local/dev | 每次清空重新 migrate | 随意 | 开发阶段可 `flyway clean` |
| preview | 自动基线 | 不允许 | 每次部署前执行 migrate |
| production | 手动基线，从 V1 开始 | 不允许（需审批） | 必须先在 dev 验证 |

### Preview 环境自动清理

Preview 环境部署前清理旧数据（避免 schema 冲突）：

```bash
# Preview 环境：删除旧数据库，重新创建
gcloud sql databases delete ${DB_NAME} --instance=${DB_INSTANCE} --quiet
gcloud sql databases create ${DB_NAME} --instance=${DB_INSTANCE}
```

---

## 8. 常见错误处理

### 错误：`Flyway migration failed: Column 'xxx' does not exist`

**原因**：应用代码引用了尚未创建的列。
**解决**：确保迁移文件编号与应用代码所需 schema 对应；必要时调整迁移文件顺序。

### 错误：`Checksum mismatch`

**原因**：已执行的迁移文件被修改。
**解决**：禁止修改已执行迁移；如需变更，创建新的 migration 文件。

### 错误：`Database is stale (max schema version: X)`

**原因**：数据库版本落后于应用期望。
**解决**：执行 `flyway migrate` 追上版本；禁止强制升级。

### 错误：`Lock acquisition failure`

**原因**：多个 Flyway 进程同时运行。
**解决**：Cloud Build 天然串行；如遇此错误，添加 `flyway.lockRetryCount=3`。

---

## 9. 迁移 Checklist（部署前必查）

- [ ] 所有迁移文件已在 dev 环境验证通过
- [ ] 迁移文件命名符合 `V{version}__{description}.sql` 规范
- [ ] 没有修改已执行过的迁移文件
- [ ] 大表迁移已分批处理，有回滚计划
- [ ] 生产迁移已在 staging 环境验证（模拟生产数据量）
- [ ] `flyway.lockRetryCount` 已配置（防止并发冲突）
- [ ] `clean-disabled: true`（生产禁止 clean）
- [ ] 备份已创建（`gcloud sql backups create`）
- [ ] 部署后验证 schema 版本（`flyway info` 输出确认）
