# 可观测性：结构化日志 + 追踪 + 告警自愈

## 核心原则

**没有可观测性，就没有可靠性。** 结构化日志是调试的第一步，追踪是排查慢请求的利器，告警是生产环境的眼睛。三个环节缺一不可，形成"日志 → 追踪 → 告警 → 自愈"闭环。

---

## 1. 结构化日志规范

### 日志格式（JSON）

所有服务必须输出 JSON 格式日志，便于 Cloud Logging 索引和 BigQuery 导出分析。

**Spring Boot 配置** (`logback-spring.xml`)：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <include resource="org/springframework/boot/logging/logback/defaults.xml"/>

    <springProperty scope="context" name="appName" source="spring.application.name"/>

    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="ch.qos.logback.core.encoder.LayoutWrappingEncoder">
            <layout class="ch.qos.logback.contrib.json.classic.JsonLayout">
                <timestampFormat>yyyy-MM-dd'T'HH:mm:ss.SSS'Z'</timestampFormat>
                <timestampFormatTimezoneId>UTC</timestampFormatTimezoneId>
                <appendLineSeparator>true</appendLineSeparator>
                <jsonFormatter class="ch.qos.logback.contrib.jackson.JacksonJsonFormatter">
                    <prettyPrint>false</prettyPrint>
                </jsonFormatter>
            </layout>
        </encoder>
    </appender>

    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
    </root>
    <logger name="com.myproject" level="DEBUG"/>
</configuration>
```

**Node.js 配置**（Pino）：

```typescript
import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  base: {
    service: process.env.SERVICE_NAME || 'unknown',
    version: process.env.SERVICE_VERSION || '0.0.0',
  },
});

// 请求中间件
export function requestLogger(req: express.Request, res: Response, next: NextFunction) {
  const start = Date.now();
  const correlationId = req.headers['x-correlation-id'] as string || generateUUID();

  req.headers['x-correlation-id'] = correlationId;

  res.on('finish', () => {
    logger.info({
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      duration: Date.now() - start,
      correlationId,
      userAgent: req.headers['user-agent'],
      ip: req.ip,
    }, 'http request');
  });

  next();
}
```

### 日志字段规范

每条日志必须包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| `timestamp` | ISO8601 | 日志时间（UTC） |
| `level` | string | TRACE/DEBUG/INFO/WARN/ERROR |
| `message` | string | 人类可读消息 |
| `correlationId` | string | 请求追踪 ID（透传 header `x-correlation-id`） |
| `service` | string | 服务名 |
| `traceId` | string | OpenTelemetry trace ID |
| `spanId` | string | OpenTelemetry span ID |
| `userId` | string | 当前登录用户 ID（若已认证） |
| `duration` | number | 请求耗时（ms，可选） |

**禁止记录**：`password`、`token`、`secret`、`authorization`、`creditCard`

### Logback 敏感信息过滤

```xml
<configuration>
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%-4relative [%thread] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>

    <!-- 敏感参数过滤 -->
    <springProfile name="production">
        <logger name="com.myproject" level="DEBUG">
            <springProperty name="appName" source="spring.application.name"/>
        </logger>
    </springProfile>
</configuration>
```

---

## 2. 分布式追踪（OpenTelemetry）

### 为什么需要 OpenTelemetry

JSON 日志只能告诉你"哪个服务出了问题"，OTel 追踪能告诉你"请求在哪个服务、哪个环节慢了多少"。两者互补，缺一不可。

### Spring Boot + OTel

**依赖** (`pom.xml`)：

```xml
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-api</artifactId>
    <version>1.32.0</version>
</dependency>
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-spring-boot-starter</artifactId>
    <version>2.0.0</version>
</dependency>
```

**配置** (`application.yml`)：

```yaml
otel:
  exporter:
    otlp:
      endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:http://localhost:4317}
  service:
    name: ${SERVICE_NAME}
  propagators: tracecontext,baggage
  resource:
    attributes:
      service.version: ${SERVICE_VERSION:0.0.0}
```

### Node.js + OTel

**依赖**：

```bash
npm install @opentelemetry/api @opentelemetry/sdk-node \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-grpc
```

**初始化** (`src/telemetry.ts`)：

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: process.env.SERVICE_NAME || 'unknown',
    [SemanticResourceAttributes.SERVICE_VERSION]: process.env.SERVICE_VERSION || '0.0.0',
  }),
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4317',
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false }, // 禁用文件系统 instrumentation（噪音大）
    }),
  ],
});

sdk.start();

process.on('SIGTERM', () => {
  sdk.shutdown().finally(() => process.exit(0));
});
```

### Correlation ID 透传

**后端（Spring Boot）**：

```java
@Component
public class CorrelationIdFilter extends OncePerRequestFilter {
    private static final String HEADER = "x-correlation-id";
    private static final Logger log = LoggerFactory.getLogger(CorrelationIdFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String correlationId = request.getHeader(HEADER);
        if (correlationId == null || correlationId.isBlank()) {
            correlationId = UUID.randomUUID().toString();
        }

        MDC.put("correlationId", correlationId);
        response.setHeader(HEADER, correlationId);

        try {
            chain.doFilter(request, response);
        } finally {
            MDC.remove("correlationId");
        }
    }
}
```

---

## 3. Cloud Monitoring 告警配置

### 核心指标（必监控）

| 指标 | 阈值 | 持续时间 | 告警级别 | 动作 |
|------|------|---------|---------|------|
| CPU 使用率 | > 80% | 1min | WARNING | 通知 |
| CPU 使用率 | > 95% | 1min | CRITICAL | 自动扩容 + 通知 |
| 请求错误率（5xx） | > 1% | 2min | WARNING | 通知 |
| 请求错误率（5xx） | > 5% | 1min | CRITICAL | 自动回滚 + 通知 |
| 实例数 | = max-instances | 1min | WARNING | 扩容评估 |
| 延迟 P99 | > 2s | 2min | WARNING | 通知 |
| 延迟 P99 | > 5s | 1min | CRITICAL | 回滚评估 |
| 内存使用率 | > 85% | 3min | WARNING | 通知 |
| 启动延迟 | > 30s | 1min | WARNING | 通知 |

### Cloud Monitoring REST API 配置

**① 创建通知渠道（Email）**：

```bash
NOTIFICATION_CHANNEL=$(curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/notificationChannels" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "email",
    "displayName": "'"${PROJECT}"-ops-email",
    "labels": { "email_address": "'"${ALERT_EMAIL}"'" }
  }' | jq -r '.name')
```

**② 创建 CPU 告警**：

```bash
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/alertPolicies" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "'"${PROJECT}"-cpu-high",
    "combiner": "OR",
    "conditions": [{
      "displayName": "CPU Usage > 80%",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"'"${SERVICE_NAME}"'\"",
        "metric": "run.googleapis.com/container/cpu/utilizations",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.8,
        "duration": "60s",
        "aggregations": [{
          "alignmentPeriod": "60s",
          "reducer": "REDUCE_MEAN",
          "groupByFields": ["resource.label.service_name"]
        }]
      }
    }],
    "notificationChannels": ["'"${NOTIFICATION_CHANNEL}"'"],
    "alertStrategy": {
      "autoClose": "1800s"
    }
  }'
```

**③ 创建错误率告警**：

```bash
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/alertPolicies" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "'"${PROJECT}"-error-rate-high",
    "combiner": "OR",
    "conditions": [{
      "displayName": "5xx Error Rate > 1%",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"'"${SERVICE_NAME}"'\" AND metric.labels.response_code_class=\"500\"",
        "metric": "run.googleapis.com/request_count",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.01,
        "duration": "120s",
        "aggregations": [{
          "alignmentPeriod": "60s",
          "reducer": "REDUCE_SUM",
          "groupByFields": ["metric.labels.response_code_class"]
        }]
      }
    }],
    "notificationChannels": ["'"${NOTIFICATION_CHANNEL}"'"]
  }'
```

**④ 创建延迟 P99 告警**：

```bash
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/alertPolicies" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "'"${PROJECT}"-latency-p99-high",
    "combiner": "OR",
    "conditions": [{
      "displayName": "Request Latency P99 > 2s",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"'"${SERVICE_NAME}"'\"",
        "metric": "run.googleapis.com/request_latencies",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 2000000000,
        "duration": "120s",
        "aggregations": [{
          "alignmentPeriod": "60s",
          "reducer": "REDUCE_PERCENTILE",
          "percentile": 99
        }]
      }
    }],
    "notificationChannels": ["'"${NOTIFICATION_CHANNEL}"'"]
  }'
```

### Cloud Logging 日志查询告警

对于业务指标（如登录失败次数），可以通过日志计数创建告警：

```bash
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/alertPolicies" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "'"${PROJECT}"-login-failure-spike",
    "combiner": "OR",
    "conditions": [{
      "displayName": "Login failures > 10 in 5min",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"'"${SERVICE_NAME}"'\" AND textPayload=~\"Login failed\"",
        "metric": "logging.googleapis.com/user/'"${SERVICE_NAME}"'_login_failures",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 10,
        "duration": "300s"
      }
    }],
    "notificationChannels": ["'"${NOTIFICATION_CHANNEL}"'"]
  }'
```

---

## 4. 告警自愈机制

### 自愈闭环

```
告警触发 → 自动诊断 → 自动执行 → 验证结果 → 通知
     ↑                                        |
     └────────────────────────────────────────┘
```

### 层级 1：自动扩容（CPU / 内存）

Cloud Run 原生支持自动扩容，但需要配置正确的 min/max 实例数。在 cloudbuild.yaml 的 Deploy step 中：

```bash
--min-instances=1      # 始终保持 1 个实例（冷启动优化）
--max-instances=10      # 防止无限扩容
--concurrency=80        # 每个实例最大并发
```

### 层级 2：错误率触发自动回滚

**Cloud Build 追加 Smoke Test + Rollback Step**：

```yaml
  # ⑦ Smoke Test + Auto Rollback
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
          echo "ERROR: Health check failed with $${HTTP_CODE}, triggering rollback..."
          gcloud run services update-traffic ${SERVICE_NAME} \
            --region=asia-east1 \
            --to-latest \
            --platform=managed 2>&1
          echo "Rollback completed"
          exit 1
        fi

        if [ "$${HTTP_CODE}" -ge 400 ]; then
          echo "WARNING: Health check returned $${HTTP_CODE}, investigating..."
        fi

        echo "Smoke test passed"
    env:
      - CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=/credential.json
    waitFor: [Deploy]
```

### 层级 3：实例数达 max 时自动扩容评估

当实例数达到 max-instances 持续 3 分钟，发送 CRITICAL 告警，人工介入评估是否需要临时提升上限：

```bash
# 临时提升 max-instances
gcloud run services update ${SERVICE_NAME} \
  --region=asia-east1 \
  --max-instances=20 \
  --platform=managed
```

### 层级 4：内存泄漏检测 + 自动重启

通过 Cloud Monitoring 内存使用率曲线判断是否出现内存泄漏（持续上升不回落）：

```
filter: resource.type="cloud_run_revision" AND resource.labels.service_name="${SERVICE_NAME}"
metric: run.googleapis.com/container/memory/utilization
condition: > 0.85 for 5min AND rising trend
action: restart service (通过 Cloud Build 重新部署)
```

### 层级 5：数据库连接池耗尽检测

| 指标 | 阈值 | 动作 |
|------|------|------|
| MySQL 连接数 | > 80% max_connections | 告警 + 连接池调优 |
| PostgreSQL 连接数 | > 50 active | 告警 + 查询优化 |
| 连接等待超时 | > 5s | 告警 + 扩容评估 |

---

## 5. 运维 Runbook（告警 → 排查 → 修复）

### CPU 高

1. Cloud Console → Cloud Run → 查看实时指标
2. `gcloud run services describe ${SERVICE_NAME} --region=asia-east1`
3. 查看 Cloud Logging：过滤 `resource.type="cloud_run_revision" AND resource.labels.service_name="${SERVICE_NAME}" AND severity="ERROR"`
4. 常见原因：死循环、频繁 GC、连接池耗尽
5. 临时缓解：`gcloud run services update ... --max-instances=5`（限制资源）

### 延迟 P99 高

1. 查 OTel 追踪：Cloud Console → Trace → 找最慢的 span
2. 重点关注：`db.query`、`external.http`、`ai.model` 类型 span
3. 常见原因：数据库慢查询、第三方 API 超时、序列化瓶颈

### 错误率升高

1. Cloud Logging 过滤 `severity="ERROR"` 查看具体异常
2. 对比最近一次部署的代码变更（GitHub commit history）
3. 如果是新部署引起：立即回滚
4. 如果非新部署：检查外部依赖（数据库、第三方 API）

### 实例数达 max

1. 临时提升上限：`--max-instances=20`
2. 分析流量来源：Cloud Console → Network → Cloud Run 入口流量
3. 判断是否正常流量（营销活动）或异常（爬虫、攻击）
4. 正常流量：评估扩容方案；异常流量：配置 Cloud Armor

---

## 6. 监控大盘（Cloud Monitoring Dashboard）

通过 REST API 创建统一大盘：

```bash
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/my-project-openclaw-492614/dashboards" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "'"${PROJECT}"-Service-Dashboard",
    "gridLayout": {
      "columns": 2,
      "widgets": [
        {
          "title": "Request Rate (RPM)",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"'"${SERVICE_NAME}"'\"",
                  "metric": "run.googleapis.com/request_count"
                }
              },
              "legendTemplate": "RPM"
            }],
            "yAxis": { "label": "RPM", "scale": "LINEAR" }
          }
        },
        {
          "title": "Error Rate (%)",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"'"${SERVICE_NAME}"'\" AND metric.labels.response_code_class=\"500\"",
                  "metric": "run.googleapis.com/request_count"
                }
              },
              "legendTemplate": "5xx Rate"
            }]
          }
        },
        {
          "title": "CPU Utilization (%)",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"'"${SERVICE_NAME}"'\"",
                  "metric": "run.googleapis.com/container/cpu/utilizations"
                }
              },
              "legendTemplate": "CPU %"
            }]
          }
        },
        {
          "title": "Latency P99 (ms)",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"'"${SERVICE_NAME}"'\"",
                  "metric": "run.googleapis.com/request_latencies"
                },
                "secondaryAggregation": {
                  "aggregation": { "reducer": "REDUCE_PERCENTILE", "percentile": 99 }
                }
              },
              "legendTemplate": "P99"
            }]
          }
        }
      ]
    }
  }'
```

---

## 7. OTel Collector（可选：聚合多服务遥测）

如果架构中有多个服务，建议部署 OTel Collector 作为统一代理：

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024

  memory_limiter:
    check_interval: 5s
    limit_mib: 512

exporters:
  googlecloud:
    project: "my-project-openclaw-492614"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [googlecloud]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [googlecloud]
```

---

## 8. SLO 指标（服务质量目标）

每个服务必须定义 SLO，并在未达到时自动告警：

| SLO | 目标 | 告警阈值 |
|-----|------|---------|
| 可用性 | 99.9%（月度约 44min 宕机） | < 99.5% |
| 延迟 P99 | < 500ms | > 1s |
| 错误率 | < 0.1%（5xx） | > 0.5% |

---

## 9. 可观测性 Checklist（部署前必查）

- [ ] JSON 结构化日志已配置（所有服务）
- [ ] Correlation ID 在请求入口生成，透传到所有 downstream 调用
- [ ] OTel SDK 已集成，Trace/span 正确生成
- [ ] Cloud Monitoring 告警策略已创建（CPU、错误率、延迟）
- [ ] 通知渠道（Email）已配置并测试
- [ ] Smoke Test + Auto Rollback 已写入 cloudbuild.yaml
- [ ] Cloud Logging 日志保留期已设置为 30 天（默认）
- [ ] Cloud Monitoring Dashboard 已创建
- [ ] SLO 目标值已定义
- [ ] Runbook 已覆盖常见告警场景
