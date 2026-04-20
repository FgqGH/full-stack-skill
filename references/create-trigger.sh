#!/bin/bash
# Cloud Build 触发器创建脚本
# 用法: ./create-trigger.sh <trigger-name> <repo-owner> <repo-name> <cloudbuild-yaml-path>
#
# 示例:
#   ./create-trigger.sh library-github-push FgqGH library-management-system backend/cloudbuild.yaml
#   ./create-trigger.sh library-frontend-push FgqGH library-management-system cloudbuild_new.yaml

set -e

TRIGGER_NAME="${1:?用法: $0 <trigger-name> <repo-owner> <repo-name> <cloudbuild-yaml-path>}"
REPO_OWNER="${2:?}"
REPO_NAME="${3:?}"
CLOUDBUILD_PATH="${4:?}"
PROJECT_ID="my-project-openclaw-492614"
SERVICE_ACCOUNT="projects/my-project-openclaw-492614/serviceAccounts/deploy-bot@my-project-openclaw-492614.iam.gserviceaccount.com"

# 获取 access token
TOKEN=$(gcloud auth print-access-token)

# 调用 Cloud Build REST API 创建触发器
RESPONSE=$(curl -s -X POST \
  "https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/triggers" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(cat <<EOF
{
  "name": "${TRIGGER_NAME}",
  "github": {
    "owner": "${REPO_OWNER}",
    "name": "${REPO_NAME}",
    "push": {
      "branch": ".*"
    }
  },
  "serviceAccount": "${SERVICE_ACCOUNT}",
  "filename": "${CLOUDBUILD_PATH}"
}
EOF
)")

# 检查返回结果
TRIGGER_ID=$(echo "${RESPONSE}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")

if [ -n "${TRIGGER_ID}" ]; then
  echo "✅ 触发器创建成功"
  echo "   名称: ${TRIGGER_NAME}"
  echo "   ID: ${TRIGGER_ID}"
  echo "   仓库: ${REPO_OWNER}/${REPO_NAME}"
  echo "   配置文件: ${CLOUDBUILD_PATH}"
else
  echo "❌ 触发器创建失败"
  echo "${RESPONSE}"
  exit 1
fi
