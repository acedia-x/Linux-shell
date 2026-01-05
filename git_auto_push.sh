#!/usr/bin/env bash

set -euo pipefail

########################################
# 基础配置区（你可按需修改）
########################################

BRANCH="main"
REMOTE="origin"
MAX_RETRY=3
RETRY_INTERVAL=3

########################################
# 基础校验
########################################

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[ERROR] 当前目录不是 Git 仓库"
  exit 1
fi

########################################
# 检测是否有变更
########################################

if git diff --quiet && git diff --cached --quiet; then
  if [[ -z "$(git status --porcelain)" ]]; then
    echo "[INFO] 未检测到任何变更，退出"
    exit 0
  fi
fi

########################################
# 添加所有变更（是否 add -A 由你自己决定）
########################################

git add -A

########################################
# 再次确认是否有内容可提交
########################################

if git diff --cached --quiet; then
  echo "[INFO] 无可提交内容"
  exit 0
fi

########################################
# 提交（提交说明你自行维护）
########################################

git commit

########################################
# 推送函数（带重试与错误分析）
########################################

push_with_retry() {
  local attempt=1

  while [[ $attempt -le $MAX_RETRY ]]; do
    echo "[INFO] 尝试推送（第 $attempt 次）"

    if git push "$REMOTE" "$BRANCH"; then
      echo "[SUCCESS] 推送成功"
      return 0
    fi

    echo "[WARN] 推送失败，分析原因中..."

    # 常见 SSH 22 端口问题
    if git push "$REMOTE" "$BRANCH" 2>&1 | grep -q "ssh_exchange_identification"; then
      echo "[ACTION] 检测到 SSH 连接异常，强制使用 GitHub SSH 443"

      mkdir -p ~/.ssh
      cat > ~/.ssh/config <<'EOF'
Host github.com
  HostName ssh.github.com
  User git
  Port 443
  IdentitiesOnly yes
EOF
    fi

    echo "[INFO] 等待 ${RETRY_INTERVAL}s 后重试"
    sleep "$RETRY_INTERVAL"
    ((attempt++))
  done

  echo "[ERROR] 达到最大重试次数，推送失败"
  exit 1
}

########################################
# 执行推送
########################################

push_with_retry

