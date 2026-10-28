#!/bin/bash
set -e
# ============================================================
# Apboa 中间件服务管理脚本
# 支持操作：build | rebuild | start | stop | restart | down | status
# 注意：脚本必须保持 LF 换行
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE_FILE="docker-compose-middleware-run.yml"
ENV_FILE=".env.middleware"
SERVICE_NAME="Apboa 中间件"

# ==================== 环境初始化 ====================
init_env() {
  if [ -f "$ENV_FILE" ]; then
    rm -rf .env
    cp "$ENV_FILE" .env
  fi
}

# ==================== 操作函数 ====================
do_build() {
  echo ">> 启动 ${SERVICE_NAME}（拉取镜像）..."
  init_env
  docker compose -f "$COMPOSE_FILE" up -d
  echo ""
  echo "${SERVICE_NAME} 启动完成"
  echo "  MySQL     : ${MYSQL_PORT:-3306}"
  echo "  Redis     : ${REDIS_PORT:-6379}"
  echo "  pgvector  : ${PG_PORT:-5432}"
}

do_rebuild() {
  echo ">> 停止并删除容器，然后重新启动..."
  init_env
  docker compose -f "$COMPOSE_FILE" down
  docker compose -f "$COMPOSE_FILE" up -d
  echo ""
  echo "${SERVICE_NAME} 重建完成"
}

do_start() {
  echo ">> 启动 ${SERVICE_NAME}..."
  init_env
  docker compose -f "$COMPOSE_FILE"  up -d
  echo "${SERVICE_NAME} 已启动"
}

do_stop() {
  echo ">> 停止 ${SERVICE_NAME}..."
  docker compose -f "$COMPOSE_FILE" stop
  echo "${SERVICE_NAME} 已停止"
}

do_restart() {
  echo ">> 重启 ${SERVICE_NAME}..."
  docker compose -f "$COMPOSE_FILE" restart
  echo "${SERVICE_NAME} 已重启"
}

do_down() {
  echo ">> 停止并删除 ${SERVICE_NAME} 容器..."
  echo "警告：数据目录不会被删除，如需清除数据请手动删除："
  echo "  rm -rf ${DATA_PATH:-./data}/mysql_data ${DATA_PATH:-./data}/redis_data ${DATA_PATH:-./data}/pgvector_data"
  docker compose -f "$COMPOSE_FILE" down
  echo "${SERVICE_NAME} 容器已删除"
}

do_status() {
  docker compose -f "$COMPOSE_FILE" ps
}

# ==================== 帮助信息 ====================
show_help() {
  echo "用法: $0 <操作>"
  echo ""
  echo "${SERVICE_NAME} 管理脚本"
  echo "服务：MySQL ${MYSQL_PORT:-3306} | Redis ${REDIS_PORT:-6379} | pgvector ${PG_PORT:-5432}"
  echo ""
  echo "操作："
  echo "  build    拉取镜像并启动所有服务"
  echo "  rebuild  停止并删除容器，然后重新启动"
  echo "  start    启动已创建的服务"
  echo "  stop     停止正在运行的服务"
  echo "  restart  重启服务"
  echo "  down     停止并删除容器（数据目录保留）"
  echo "  status   查看服务运行状态"
  echo ""
  echo "说明："
  echo "  部署前请先编辑 ${ENV_FILE} 设置密码等配置"
  echo "  down 操作不会删除数据目录，数据持久化安全"
  echo ""
  echo "示例："
  echo "  $0 build     # 首次部署"
  echo "  $0 status    # 查看当前运行状态"
  echo "  $0 down      # 停止服务（保留数据）"
}

# ==================== 主逻辑 ====================
case "${1:-}" in
  build)   do_build   ;;
  rebuild) do_rebuild ;;
  start)   do_start   ;;
  stop)    do_stop    ;;
  restart) do_restart ;;
  down)    do_down    ;;
  status)  do_status  ;;
  *)       show_help  ;;
esac
