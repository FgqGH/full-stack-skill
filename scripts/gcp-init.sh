#!/usr/bin/env bash
#
# gcp-init.sh — GCP 项目初始化脚本
# 用法: ./gcp-init.sh <PROJECT_ID> [--force]
#
# 作用：首次在新 GCP Project 上部署前，执行所有必要初始化。
#       幂等设计：重复执行是安全的，不会覆盖已存在的资源。
#
# 执行前提：
#   1. gcloud CLI 已安装且已 `gcloud auth login`
#   2. 当前用户有 Project Owner 权限（或足够创建 Service Account / Secret / Role 的权限）
#
# 包含步骤：
#   ① 启用必要 API
#   ② 创建 deploy-bot Service Account
#   ③ 授予 deploy-bot 所需 IAM 角色
#   ④ 创建 Secret Manager secrets（JWT_SECRET / DB_PASSWORD）
#   ⑤ 授予 deploy-bot 读取 secrets 的权限
#   ⑥ 配置 Artifact Registry（创建仓库）
#   ⑦ 验证初始化结果
#

set -euo pipefail

# ─── 颜色输出 ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── 参数解析 ────────────────────────────────────────────────
PROJECT_ID=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    --)      shift; break ;;
    -*)      error "未知参数: $1"; exit 1 ;;
    *)       PROJECT_ID="$1"; shift ;;
  esac
done

if [[ -z "$PROJECT_ID" ]]; then
  error "用法: $0 <PROJECT_ID> [--force]"
  error "示例: $0 my-project-openclaw-492614"
  exit 1
fi

REGION="${REGION:-asia-east1}"
DEPLOY_BOT="deploy-bot"

# ─── 前置检查 ────────────────────────────────────────────────
info "检查 gcloud CLI 登录状态..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
  error "未登录。请先运行: gcloud auth login"
  exit 1
fi

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
info "当前账户: ${ACTIVE_ACCOUNT}"

# 设置项目
info "设置当前项目: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}" --quiet

# ─── ① 启用 API ─────────────────────────────────────────────
info "① 启用必要 GCP API..."

APIS=(
  "cloudbuild.googleapis.com"
  "run.googleapis.com"
  "secretmanager.googleapis.com"
  "sqladmin.googleapis.com"
  "monitoring.googleapis.com"
  "logging.googleapis.com"
  "artifactregistry.googleapis.com"
  "compute.googleapis.com"
)

for api in "${APIS[@]}"; do
  if gcloud services list --enabled --format="value(name)" 2>/dev/null | grep -q "^${api}$"; then
    success "API ${api} — 已启用"
  else
    info "启用 ${api}..."
    if gcloud services enable "${api}" --project="${PROJECT_ID}" 2>&1 | grep -q -E "(enabled|already enabled)"; then
      success "API ${api} — 启用成功"
    else
      # 有些 API 启用输出不含 enabled，需要容错
      gcloud services enable "${api}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
      success "API ${api} — 已处理"
    fi
  fi
done

# ─── ② 创建 deploy-bot Service Account ───────────────────────
info "② 创建 Service Account: ${DEPLOY_BOT}@${PROJECT_ID}.iam.gserviceaccount.com..."

BOT_EMAIL="${DEPLOY_BOT}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "${BOT_EMAIL}" --project="${PROJECT_ID}" 2>/dev/null | grep -q "email:"; then
  success "Service Account ${BOT_EMAIL} — 已存在"
else
  gcloud iam service-accounts create "${DEPLOY_BOT}" \
    --display-name="Deploy Bot for CI/CD" \
    --project="${PROJECT_ID}" 2>/dev/null
  success "Service Account ${BOT_EMAIL} — 创建成功"
fi

# ─── ③ 授予 IAM 角色 ─────────────────────────────────────────
info "③ 授予 ${DEPLOY_BOT} 所需 IAM 角色..."

# 角色列表（按用途分组）
ROLES=(
  "roles/artifactregistry.admin"       # 推送/拉取镜像
  "roles/run.admin"                    # 部署 Cloud Run
  "roles/iam.serviceAccountUser"       # 以 Service Account 身份运行
  "roles/cloudsql.admin"               # 管理 Cloud SQL 实例
  "roles/storage.objectAdmin"          # 读写 GCS（Artifact Registry 底层依赖）
  "roles/secretmanager.secretAccessor" # 读取 Secret Manager
  "roles/monitoring.admin"             # 创建告警策略/Dashboard
  "roles/logging.admin"                # 管理日志配置
)

# 获取 bot 的正式 member 标识
BOT_MEMBER="serviceAccount:${BOT_EMAIL}"

for role in "${ROLES[@]}"; do
  # 检查是否已有该角色
  if gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten="bindings[].members" \
    --filter="bindings.members:${BOT_MEMBER} AND bindings.role:${role}" \
    --format="value(bindings.role)" 2>/dev/null | grep -q "^${role}$"; then
    success "角色 ${role} — 已存在"
  else
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="${BOT_MEMBER}" \
      --role="${role}" \
      --quiet 2>/dev/null
    success "角色 ${role} — 授予成功"
  fi
done

# ─── ④ 创建 Secret Manager Secrets ───────────────────────────
info "④ 创建 Secret Manager secrets..."

# JWT_SECRET（如果不存在）
if gcloud secrets describe JWT_SECRET --project="${PROJECT_ID}" 2>/dev/null; then
  success "Secret JWT_SECRET — 已存在"
else
  # 生成随机 JWT 密钥
  JWT_VALUE=$(openssl rand -base64 32)
  echo -n "${JWT_VALUE}" | gcloud secrets create JWT_SECRET \
    --data-file=- \
    --project="${PROJECT_ID}" \
    --replication-policy="automatic" 2>/dev/null
  success "Secret JWT_SECRET — 创建成功（值已生成）"
fi

# DB_PASSWORD（如果不存在）
if gcloud secrets describe DB_PASSWORD --project="${PROJECT_ID}" 2>/dev/null; then
  success "Secret DB_PASSWORD — 已存在"
else
  # 生成随机数据库密码
  DB_VALUE=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
  echo -n "${DB_VALUE}" | gcloud secrets create DB_PASSWORD \
    --data-file=- \
    --project="${PROJECT_ID}" \
    --replication-policy="automatic" 2>/dev/null
  success "Secret DB_PASSWORD — 创建成功（值已生成，请妥善保管）"
fi

# ─── ⑤ 授予 deploy-bot 读取 secrets 的权限 ─────────────────
info "⑤ 授予 ${DEPLOY_BOT} 读取 secrets 的权限..."

for secret in JWT_SECRET DB_PASSWORD; do
  if gcloud secrets add-iam-policy-binding "${secret}" \
    --member="${BOT_MEMBER}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="${PROJECT_ID}" \
    --quiet 2>/dev/null; then
    success "Secret ${secret} — secretAccessor 权限已授予"
  else
    # 幂等：绑定可能已存在，但 add-iam-policy-binding 会合并，不会报错
    success "Secret ${secret} — 权限已配置"
  fi
done

# ─── ⑥ 配置 Artifact Registry ─────────────────────────────────
info "⑥ 配置 Artifact Registry（asia-east1）..."

REPO_NAME="${REGION}-docker-repo"

if gcloud artifacts repositories describe "${REPO_NAME}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}" 2>/dev/null | grep -q "name:"; then
  success "Artifact Registry 仓库 ${REPO_NAME} — 已存在"
else
  gcloud artifacts repositories create "${REPO_NAME}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Docker images for ${PROJECT_ID}" \
    --project="${PROJECT_ID}" 2>/dev/null
  success "Artifact Registry 仓库 ${REPO_NAME} — 创建成功"
fi

# 配置 docker auth
gcloud auth configure-docker \
  "${REGION}-docker.pkg.dev" \
  --quiet 2>/dev/null
success "Docker auth — 已配置"

# ─── ⑦ 验证 ─────────────────────────────────────────────────
info "⑦ 验证初始化结果..."

echo ""
echo "─────────────────────────────────────────────"
echo "  初始化验证报告"
echo "─────────────────────────────────────────────"

# API
info "已启用 API:"
for api in "${APIS[@]}"; do
  if gcloud services list --enabled --format="value(name)" 2>/dev/null | grep -q "^${api}$"; then
    success "  ✓ ${api}"
  else
    warn "  ✗ ${api} — 未启用"
  fi
done

# Service Account
echo ""
if gcloud iam service-accounts describe "${BOT_EMAIL}" --project="${PROJECT_ID}" 2>/dev/null | grep -q "email:"; then
  success "Service Account: ${BOT_EMAIL}"
else
  error "Service Account: ${BOT_EMAIL} — 不存在!"
fi

# Secrets
echo ""
for secret in JWT_SECRET DB_PASSWORD; do
  if gcloud secrets describe "${secret}" --project="${PROJECT_ID}" 2>/dev/null; then
    success "Secret ${secret}: 已创建"
  else
    error "Secret ${secret}: 不存在!"
  fi
done

# Artifact Registry
echo ""
if gcloud artifacts repositories describe "${REPO_NAME}" --location="${REGION}" --project="${PROJECT_ID}" 2>/dev/null | grep -q "name:"; then
  success "Artifact Registry: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"
else
  error "Artifact Registry: 仓库不存在!"
fi

echo ""
echo "─────────────────────────────────────────────"
echo -e "  ${GREEN}GCP 初始化完成！${NC}"
echo "─────────────────────────────────────────────"
echo ""
echo "  重要信息："
echo "  • deploy-bot: ${BOT_EMAIL}"
echo "  • Region:     ${REGION}"
echo "  • Artifact Registry: ${REGION}-docker.pkg.dev/${PROJECT_ID}"
echo "  • Secrets:    JWT_SECRET, DB_PASSWORD（已创建，请从 Secret Manager 获取实际值）"
echo ""
echo "  下一步："
echo "  1. 获取 DB_PASSWORD 值（后续使用）:"
echo "     gcloud secrets versions access latest --secret=DB_PASSWORD --project=${PROJECT_ID}"
echo "  2. 创建 Cloud SQL 实例（如果尚未创建）:"
echo "     gcloud sql instances create my-instance --tier=db-f1-micro --region=${REGION} --project=${PROJECT_ID}"
echo "  3. 开始部署项目"
echo ""

