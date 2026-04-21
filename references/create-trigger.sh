#!/bin/bash
# =============================================================================
# Cloud Build 触发器创建脚本（REST API 版本）
# 用法:
#   # 后端触发器（只监听 backend/ 目录变更）
#   ./create-trigger.sh backend <project-name> <repo-owner> <repo-name>
#
#   # 前端触发器（只监听 frontend/ 目录变更）
#   ./create-trigger.sh frontend <project-name> <repo-owner> <repo-name>
#
# 示例:
#   ./create-trigger.sh backend library FgqGH library-management-system
#   ./create-trigger.sh frontend library FgqGH library-management-system
# =============================================================================
set -euo pipefail

TRIGGER_TYPE="${1:?用法: $0 <backend|frontend> <project-name> <repo-owner> <repo-name>}"
PROJECT_NAME="${2:?}"
REPO_OWNER="${3:?}"
REPO_NAME="${4:?}"

PROJECT_ID="my-project-openclaw-492614"
REGION="asia-east1"
DEPLOY_BOT="deploy-bot@my-project-openclaw-492614.iam.gserviceaccount.com"
AR_REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}"

# Cloud SQL 连接信息（通过 substitutions 传递，不泄露）
CLOUD_SQL_INSTANCE="my-project-openclaw"
DB_NAME="appdb"
DB_USERNAME="appuser"

# 确定触发器名称和路径过滤
if [[ "$TRIGGER_TYPE" == "backend" ]]; then
  TRIGGER_NAME="${PROJECT_NAME}-backend-push"
  CLOUDBUILD_PATH="backend/cloudbuild.yaml"
  INCLUDE_PATH="backend/**"
  EXCLUDE_PATH="frontend/**"
  IMAGE_PREFIX="${PROJECT_NAME}"
  SERVICE_NAME="${PROJECT_NAME}"
elif [[ "$TRIGGER_TYPE" == "frontend" ]]; then
  TRIGGER_NAME="${PROJECT_NAME}-frontend-push"
  CLOUDBUILD_PATH="frontend/cloudbuild.yaml"
  INCLUDE_PATH="frontend/**"
  EXCLUDE_PATH="backend/**"
  IMAGE_PREFIX="${PROJECT_NAME}"
  SERVICE_NAME="${PROJECT_NAME}-frontend"
else
  echo "ERROR: TRIGGER_TYPE must be 'backend' or 'frontend'"
  exit 1
fi

log_info() { echo "[INFO]  $*"; }
log_ok()   { echo "[OK]   $*"; }

log_info "创建触发器: $TRIGGER_NAME"
log_info "仓库: $REPO_OWNER/$REPO_NAME"
log_info "路径过滤: includes=$INCLUDE_PATH, excludes=$EXCLUDE_PATH"

# 获取 access token（不在字符串中展开，避免二次解析问题）
TOKEN="$(gcloud auth print-access-token)"

# 构造 JSON payload
PAYLOAD=$(cat <<EOF
{
  "name": "${TRIGGER_NAME}",
  "github": {
    "owner": "${REPO_OWNER}",
    "name": "${REPO_NAME}",
    "push": {
      "branch": ".*",
      "pathFilters": {
        "includes": ["${INCLUDE_PATH}"],
        "excludes": ["${EXCLUDE_PATH}"]
      }
    }
  },
  "serviceAccount": "projects/${PROJECT_ID}/serviceAccounts/${DEPLOY_BOT}",
  "filename": "${CLOUDBUILD_PATH}",
  "substitutions": {
    "_PROJECT_NAME": "${PROJECT_NAME}",
    "_REGION": "${REGION}",
    "_AR_REPO": "${AR_REPO}",
    "_IMAGE_PREFIX": "${IMAGE_PREFIX}",
    "_SERVICE_NAME": "${SERVICE_NAME}",
    "_DB_HOST": "${CLOUD_SQL_INSTANCE}",
    "_DB_PORT": "5432",
    "_DB_NAME": "${DB_NAME}",
    "_DB_USERNAME": "${DB_USERNAME}"
  }
}
EOF
)

# 调用 Cloud Build REST API
RESPONSE=$(curl -s -X POST \
  "https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/triggers" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

TRIGGER_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")

if [[ -n "$TRIGGER_ID" ]]; then
  echo ""
  log_ok "触发器创建成功"
  echo "   名称:     $TRIGGER_NAME"
  echo "   ID:       $TRIGGER_ID"
  echo "   仓库:     $REPO_OWNER/$REPO_NAME"
  echo "   配置文件: $CLOUDBUILD_PATH"
  echo "   路径过滤: $INCLUDE_PATH (excludes: $EXCLUDE_PATH)"
  echo ""
  echo "Substitutions 变量（Cloud Build 自动注入）:"
  echo "   _PROJECT_NAME=$PROJECT_NAME"
  echo "   _REGION=$REGION"
  echo "   _AR_REPO=$AR_REPO"
  echo "   _IMAGE_PREFIX=$IMAGE_PREFIX"
  echo "   _SERVICE_NAME=$SERVICE_NAME"
  echo "   _DB_HOST=$CLOUD_SQL_INSTANCE"
  echo "   _DB_PORT=5432"
  echo "   _DB_NAME=$DB_NAME"
  echo "   _DB_USERNAME=$DB_USERNAME"
else
  echo ""
  echo "ERROR: 触发器创建失败"
  echo "$RESPONSE"
  exit 1
fi
