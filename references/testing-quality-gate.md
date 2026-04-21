# 测试体系与质量门禁

## 核心原则

**测试失败 = 部署阻断**。没有借口，没有绕过，质量不过关的代码不允许进入生产。

---

## 1. 测试分类与覆盖率要求

### 后端（Spring Boot）

| 层级 | 工具 | 覆盖率门禁 | 运行时机 |
|------|------|-----------|---------|
| 单元测试 | JUnit 5 + Mockito | > 70% | CI（每次 push） |
| 集成测试 | SpringBootTest + Testcontainers | > 50% | CI（每次 push） |
| API 契约测试 | Dredd + OpenAPI | 100% 路径覆盖 | CI（Contract Test step） |
| 性能测试 | JMeter / k6 | P99 < 2s | 发布前手动 |

### 后端（Node.js）

| 层级 | 工具 | 覆盖率门禁 | 运行时机 |
|------|------|-----------|---------|
| 单元测试 | Jest | > 70% | CI（每次 push） |
| 集成测试 | Supertest | > 50% | CI（每次 push） |
| API 契约测试 | Dredd + OpenAPI | 100% 路径覆盖 | CI（Contract Test step） |

### 前端（Flutter Web）

| 层级 | 工具 | 覆盖率门禁 | 运行时机 |
|------|------|-----------|---------|
| Widget Test | flutter_test | > 50% | CI（每次 push） |
| Integration Test | integration_test | > 30% | CI（每次 push） |
| Lighthouse CI | lighthouse | Performance > 90 | CI（每次 push） |

---

## 2. JaCoCo 覆盖率配置（Spring Boot）

### `pom.xml` 添加 JaCoCo 插件

```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.jacoco</groupId>
            <artifactId>jacoco-maven-plugin</artifactId>
            <version>0.8.11</version>
            <executions>
                <execution>
                    <id>prepare-agent</id>
                    <goals>
                        <goal>prepare-agent</goal>
                    </goals>
                </execution>
                <execution>
                    <id>report</id>
                    <phase>test</phase>
                    <goals>
                        <goal>report</goal>
                    </goals>
                </execution>
                <execution>
                    <id>check</id>
                    <goals>
                        <goal>check</goal>
                    </goals>
                    <configuration>
                        <rules>
                            <rule>
                                <element>BUNDLE</element>
                                <limits>
                                    <limit>
                                        <counter>LINE</counter>
                                        <value>COVEREDRATIO</value>
                                        <minimum>0.70</minimum>
                                    </limit>
                                    <limit>
                                        <counter>BRANCH</counter>
                                        <value>COVEREDRATIO</value>
                                        <minimum>0.60</minimum>
                                    </limit>
                                </limits>
                            </rule>
                        </rules>
                    </configuration>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```

> `jacoco:check` 在 `mvn test` 时自动执行，覆盖率不达标则 build 失败。

---

## 3. Jest 覆盖率配置（Node.js）

### `package.json` 添加 Jest 配置

```json
{
  "scripts": {
    "test": "jest",
    "test:coverage": "jest --coverage --coverageThreshold='{\"global\":{\"branches\":60,\"functions\":70,\"lines\":70,\"statements\":70}}'"
  },
  "jest": {
    "collectCoverageFrom": [
      "src/**/*.ts",
      "!src/**/*.d.ts",
      "!src/index.ts"
    ],
    "coverageThreshold": {
      "global": {
        "branches": 60,
        "functions": 70,
        "lines": 70,
        "statements": 70
      }
    }
  }
}
```

---

## 4. Flutter 覆盖率配置

### `pubspec.yaml` 添加 dev dependency

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  mockito: ^5.4.0
  build_runner: ^2.4.0
```

### `flutter_test` 配置（可选，在 `test/` 目录下）

```dart
// test/all_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 覆盖率报告通过 `flutter test --coverage` 生成
  // 使用 `genhtml coverage/lcov.info -o coverage/html` 查看报告
}
```

---

## 5. Lighthouse CI 配置（Flutter Web）

### `lighthouserc.json`

```json
{
  "ci": {
    "collect": {
      "startServerCommand": "flutter run -d web-server --web-port=9222",
      "startServerReadyPattern": "The web-server device type is not supported",
      "url": ["http://localhost:9222"],
      "numberOfRuns": 3
    },
    "assert": {
      "assertions": {
        "categories:performance": ["error", {"minScore": 0.9}],
        "categories:accessibility": ["error", {"minScore": 0.9}],
        "categories:best-practices": ["error", {"minScore": 0.9}],
        "categories:seo": ["error", {"minScore": 0.9}],
        "first-contentful-paint": ["error", { "maxNumericValue": 2000 }],
        "largest-contentful-paint": ["error", { "maxNumericValue": 4000 }],
        "cumulative-layout-shift": ["error", { "maxNumericValue": 0.1 }]
      }
    }
  }
}
```

### Cloud Build 集成 Lighthouse

在 Flutter cloudbuild.yaml 的 Install Flutter & Build step **之后**添加：

```yaml
  # Flutter Build 之后添加 Lighthouse CI
  - name: node:20
    id: Lighthouse CI
    entrypoint: npx
    args:
      - "@lhci/cli"
      - autorun
    env:
      - LHCI_GITHUB_APP_TOKEN=${_LHCI_GITHUB_APP_TOKEN}
    waitFor: [Install Flutter & Build]
```

---

## 6. Cloud Build 测试执行顺序

### 后端（Spring Boot）

```yaml
steps:
  # 1. Contract Test（OpenAPI 契约验证）
  - name: node:20
    id: Start Mock Server
    entrypoint: npx
    args: ["@stoplight/prism", "mock", "backend/openapi.yaml", "--port", "4010"]
    background: true
    waitFor: ["-"]

  - name: node:20
    id: Contract Test
    entrypoint: npx
    args: ["dredd", "backend/openapi.yaml", "http://localhost:4010", "--config", "backend/dredd.yml"]
    waitFor: [Start Mock Server]

  # 2. 单元测试 + 覆盖率检查（JaCoCo）
  - name: maven:3.9-eclipse-temurin-17
    id: Test
    entrypoint: mvn
    args: [test, -q]
    dir: backend
    waitFor: [Contract Test]

  # 3. 打包（-DskipTests 已在 Package step 后无效，这里只打包）
  - name: maven:3.9-eclipse-temurin-17
    id: Build Package
    entrypoint: mvn
    args: [package, -DskipTests, -q]
    dir: backend
    waitFor: [Test]
```

> **注意**：`mvn test` 已经包含 `jacoco:check`，覆盖率不达标会直接失败。

### 后端（Node.js）

```yaml
steps:
  # 1. Contract Test
  - name: node:20
    id: Start Mock Server
    entrypoint: npx
    args: ["@stoplight/prism", "mock", "backend/openapi.yaml", "--port", "4010"]
    background: true
    waitFor: ["-"]

  - name: node:20
    id: Contract Test
    entrypoint: npx
    args: ["dredd", "backend/openapi.yaml", "http://localhost:4010", "--config", "backend/dredd.yml"]
    waitFor: [Start Mock Server]

  # 2. 单元测试 + 覆盖率检查
  - name: node:20
    id: Test
    entrypoint: npm
    args: [run, test:coverage, --prefix, backend]
    dir: .
    waitFor: [Contract Test]

  # 3. 构建
  - name: node:20
    id: Build
    entrypoint: npm
    args: [run, build, --prefix, backend]
    waitFor: [Test]
```

### 前端（Flutter Web）

```yaml
steps:
  # 1. 安装 Flutter & Build
  - name: ubuntu:22.04
    id: Install Flutter & Build
    entrypoint: bash
    args: [...]
    waitFor: ["-"]

  # 2. Widget Tests + 覆盖率
  - name: ubuntu:22.04
    id: Widget Test
    entrypoint: bash
    args:
      - -c
      - |
        export PATH="/opt/flutter/bin:$PATH"
        cd frontend
        flutter test --coverage
        # 覆盖率检查
        if [ ! -f coverage/lcov.info ]; then echo "No coverage"; exit 1; fi
        lines=$(grep -c "SF:" coverage/lcov.info || echo 0)
        echo "Covered lines: $lines"
    waitFor: [Install Flutter & Build]

  # 3. Lighthouse CI
  - name: node:20
    id: Lighthouse CI
    entrypoint: npx
    args: ["@lhci/cli", "autorun"]
    waitFor: [Widget Test]

  # 4. Docker 构建
  - name: gcr.io/cloud-builders/docker
    id: Build Docker Image
    args: [...]
    waitFor: [Lighthouse CI]
```

---

## 7. 测试命名规范

### 后端测试文件结构

```
backend/
├── src/test/java/com/{org}/{project}/
│   ├── controller/
│   │   └── {Resource}ControllerTest.java      # @WebMvcTest
│   ├── service/
│   │   └── {Service}ServiceTest.java          # @ExtendWith(MockitoExtension)
│   ├── mapper/
│   │   └── {Mapper}MapperTest.java             # @MyBatisTest
│   └── integration/
│       └── {Feature}IntegrationTest.java       # @SpringBootTest + Testcontainers
```

### 测试方法命名

```java
@Test
void login_withValidCredentials_returnsToken() { }

@Test
void login_withInvalidPassword_returns401() { }

@Test
void getUser_withValidId_returnsUser() { }

@Test
void getUser_withInvalidId_returns404() { }
```

### Node.js 测试文件结构

```
backend/
├── src/
│   ├── routes/
│   │   └── auth.test.ts
│   ├── services/
│   │   └── auth.service.test.ts
│   └── integration/
│       └── auth.integration.test.ts
```

---

## 8. 质量门禁检查清单（合并到 develop 前）

- [ ] 所有单元测试通过（`mvn test` / `npm test`）
- [ ] 覆盖率达标（JaCoCo/Jest: line > 70%）
- [ ] Contract Test 通过（100% API 路径覆盖）
- [ ] 没有新增 `console.error` / 未捕获异常
- [ ] 没有硬编码的 secrets 或测试数据
- [ ] `git diff --stat` 文件数量正常（排除 node_modules 等）
- [ ] SonarQube QG 通过（如果有配置）

---

## 9. Subagent 测试任务指令

### 后端 subagent 必须完成

```json
{
  "task": "...
  测试要求：
  1. Controller 层必须有 @WebMvcTest 测试（模拟 HTTP 请求）
  2. Service 层必须有单元测试（Mock 外部依赖）
  3. 集成测试使用 @SpringBootTest（真实 Spring 上下文）
  4. 所有测试方法命名：`method_condition_expectedResult`
  5. pom.xml 必须配置 JaCoCo，覆盖率门禁：line > 70%
  6. 测试数据使用 Faker 或随机生成，不用固定值
  7. 第三方依赖（DB、Redis）用 Testcontainers 隔离
  "
}
```

### 前端 subagent 必须完成

```json
{
  "task": "...
  测试要求：
  1. 每个页面必须有 Widget Test（render + interaction）
  2. 关键用户流程必须有 Integration Test
  3. API 调用层必须 Mock Dio（不用真实网络）
  4. pubspec.yaml 必须添加 integration_test 和 mockito
  5. 测试数据用 Faker 或 mockito 生成，不用固定值
  "
}
```
