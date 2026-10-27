# Apboa Helm Chart

把 `docker/docker-compose-*.yml` 那套编排翻译成 Kubernetes 资源。服务、端口、环境变量、
卷挂载、资源上限、安全加固项都与 compose 文件一一对应，可以用 compose 的 `.env` 值直接填过来。

```
deploy/helm/apboa
├── Chart.yaml
├── values.yaml                  # 默认值（内置中间件、单副本）
├── values-single-node.yaml      # 单节点集群覆盖值（RWO + NodePort）
├── files/db_init.sql            # 与 sql/db_init.sql 保持一致的副本
└── templates/
    ├── _helpers.tpl             # 命名、标签、中间件地址、环境变量片段
    ├── _volumes.tpl             # .apboa / /opt/tools / 日志卷
    ├── secret.yaml              # MySQL/Redis/PG 密码 + JWT（首次生成后复用）
    ├── configmap-mysql-initdb.yaml
    ├── pvc.yaml
    ├── mysql.yaml               # StatefulSet + Service
    ├── redis.yaml
    ├── pgvector.yaml
    ├── ollama.yaml              # 默认关闭
    ├── console.yaml             # runner-console  3060
    ├── runtime.yaml             # runner-runtime  3061
    ├── proxy.yaml               # runner-proxy    3062（只读根文件系统 + caps 最小化）
    ├── gateway.yaml             # runner-gateway  无固定端口，hostNetwork
    ├── websocket.yaml           # runner-websocket 3064
    ├── file.yaml                # runner-file（仅 local 存储模式）
    └── frontend.yaml            # Nginx + 静态资源 80，可选 Ingress
```

## 与 compose 的对应关系

| compose 服务 | K8s 工作负载 | 端口 | 说明 |
| --- | --- | --- | --- |
| `apboa-mysql` | StatefulSet | 3306 | 首次初始化执行 `db_init.sql` |
| `apboa-redis` | Deployment + PVC | 6379 | 带密码 |
| `apboa-pgvector` | StatefulSet | 5432 | RAG 向量库 |
| `ollama` | Deployment | 11434 | 默认关闭 |
| `apboa-console` | Deployment + Service | 3060 | 管理控制台 |
| `apboa-runtime` | Deployment + Service | 3061 | AI 运行时，可多副本 |
| `apboa-proxy` | Deployment + Service | 3062 | 执行不可信命令，安全加固最严 |
| `apboa-gateway` | Deployment（hostNetwork） | 动态 | 已发布 API 应用的数据面 |
| `apboa-websocket` | Deployment + Service | 3064 | 消息推送 |
| `apboa-file` | Deployment | 无 | 仅 `storageMode=local` 需要 |
| `apboa-frontend` | Deployment + Service (+Ingress) | 80 | 静态资源 + API 反向代理 |

## 1. 准备镜像

Helm 只负责编排，镜像仍需自己构建并推到集群能拉的仓库。仓库根目录下：

```bash
# 以 console 为例，其余按 docker/<组件>/Dockerfile 同理
docker build -f docker/console/Dockerfile -t harbor.example.com/apboa/docker-apboa-console:1.0.0 .
docker push harbor.example.com/apboa/docker-apboa-console:1.0.0
```

组件与镜像名对应：`console / runtime / proxy / gateway / websocket / file / frontend`
→ `docker-apboa-<组件>:<tag>`。前端镜像构建时会打入 `VITE_APP_BASE_API`、`VITE_APP_CONTEXT_PATH`，
实际部署请传生产值。

本地集群（kind / minikube）可以直接 `kind load docker-image ...` 或 `minikube image load`，
免推仓库。

安装时用 `global.imageRegistry` + 各组件的 `image.tag` 指过去：

```bash
helm install apboa ./deploy/helm/apboa -n apboa --create-namespace \
  --set global.imageRegistry=harbor.example.com/apboa \
  --set console.image.tag=1.0.0 --set runtime.image.tag=1.0.0 \
  --set proxy.image.tag=1.0.0 --set gateway.image.tag=1.0.0 \
  --set websocket.image.tag=1.0.0 --set frontend.image.tag=1.0.0 \
  --set global.imagePullSecrets[0].name=harbor-cred
```

> 默认 tag 是 `latest` 且 `pullPolicy: IfNotPresent`，同名 tag 覆盖后需要
> `kubectl rollout restart`。生产建议用不可变 tag 或 digest。

## 2. 安装

### 2.1 一体化部署（内置 MySQL / Redis / pgvector）

```bash
helm install apboa ./deploy/helm/apboa -n apboa --create-namespace
kubectl -n apboa get pods -w
```

首次启动顺序：MySQL 初始化 → console/runtime 就绪；其余服务在此之前会 CrashLoop 重启几次，
属正常现象（没有配 initContainer 等待，避免额外拉取 busybox 镜像）。

### 2.2 单节点集群

```bash
helm install apboa ./deploy/helm/apboa -n apboa --create-namespace \
  -f ./deploy/helm/apboa/values-single-node.yaml
kubectl -n apboa get svc apboa-frontend   # NodePort
```

### 2.3 复用已有中间件（生产推荐）

```bash
helm install apboa ./deploy/helm/apboa -n apboa --create-namespace \
  --set middleware.mysql.enabled=false \
  --set external.mysql.host=mysql.internal --set external.mysql.port=3306 \
  --set external.mysql.database=apboa_next --set external.mysql.username=apboa \
  --set external.mysql.password='***' \
  --set middleware.redis.enabled=false \
  --set external.redis.host=redis.internal --set external.redis.password='***' \
  --set middleware.pgvector.enabled=false \
  --set external.pgvector.host=pg.internal --set external.pgvector.database=apboa_vector \
  --set external.pgvector.username=postgres --set external.pgvector.password='***'
```

外部模式下 MySQL/Redis/pgvector 的 StatefulSet/PVC 不会创建，密码写进同一个 Secret
（`apboa-secret`），应用侧环境变量不变。外部库需自行初始化 schema（见第 6 节）。

## 3. 访问

```bash
# 默认 ClusterIP，本地验证
kubectl -n apboa port-forward svc/apboa-frontend 8080:80
# 浏览器打开 http://localhost:8080/web/

# 走域名 + Ingress
helm upgrade apboa ./deploy/helm/apboa -n apboa \
  --set frontend.ingress.enabled=true \
  --set frontend.ingress.host=apboa.example.com
```

默认管理员来自 `db_init.sql`：`admin / admin@gmail.com`。数据库密码：

```bash
kubectl -n apboa get secret apboa-secret \
  -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d
```

## 4. 关键配置

| values | 对应 compose | 说明 |
| --- | --- | --- |
| `global.imageRegistry` | `DOCKER_REGISTRY` | 不加协议头、不带结尾斜杠 |
| `global.timezone` | `TZ` | 默认 Asia/Shanghai |
| `app.jwtSecret` | `JWT_SECRET` | 留空自动生成并复用 |
| `app.storageMode` | `APBOA_STORAGE_MODE` | `shared` / `local` |
| `app.workspaceCapacityMb` | `WORKSPACE_CAPACITY_MB` | |
| `<组件>.javaHeapPercentage` | `*_JAVA_HEAP_PERCENTAGE` | 依赖 `resources.limits.memory` |
| `proxy.shell.*` | `SHELL_DEFAULT_TIMEOUT` 等 | 见 compose 的 `SHELLPROXY_*` |
| `gateway.hostNetwork` | `network_mode: host` | 见下方限制 |
| `persistence.data` | `${DATA_PATH}/.apboa` | 租户 skills / workspaces，四个服务共享 |
| `persistence.tools` | `${DATA_PATH}/runtime-tools` 等 | 按组件 subPath 隔离 |
| `persistence.logs` | `${LOG_PATH}` | 默认 emptyDir；`enabled=true` 落盘 |

> **JVM 堆**：entrypoint 用 `-XX:MaxRAMPercentage` 按容器内存上限算堆，改 `resources.limits.memory`
> 就等于改堆大小。不要移除 memory limit，否则 JVM 会按节点内存计算，直接把节点打满。

## 5. 与 compose 的差异（务必看）

| 项 | compose | K8s 侧 | 影响 |
| --- | --- | --- | --- |
| 网关网络 | `network_mode: host` | `hostNetwork: true` + `ClusterFirstWithHostNet` | 已发布 API 的端口直接占用**节点端口**；端口冲突需靠节点调度隔离，且防火墙要放行 |
| 网关上游地址 | `127.0.0.1:3062` / `127.0.0.1:3060` | 走 `apboa-proxy` / `apboa-console` Service | Pod 之间不再共享 localhost |
| 共享目录 | 宿主机同一目录 | 单个 PVC（默认 RWX） | 多节点必须 RWX 存储（NFS/CephFS）；单节点可改 RWO |
| 进程/线程上限 | `pids_limit` | **无 Pod 级等价字段** | 需要时由 kubelet `--pod-max-pids` 或 RuntimeClass 承担 |
| 端口发布 | `ports:` | Service（NodePort/LoadBalancer/Ingress） | 前端默认 ClusterIP |
| 服务发现 | 容器名 | 同名 Service（`apboa-console` 等）| 见下方命名约束 |
| 初始化 SQL | initdb 目录挂载 | ConfigMap 挂载同一目录 | 语义一致：仅数据目录为空时执行 |
| 启动编排 | `depends_on: condition: healthy` | readiness + 重启退避 | 依赖未就绪时业务 Pod 会先失败重启 |

### 命名约束（重要）

前端镜像里的 `nginx.conf` 是在**构建期**写入的，控制台上游写死为 `apboa-console:3060`。
因此：

* 不要随意改 `namePrefix`（默认 `apboa`），否则 `/api/` 反代会 502；
* 确实需要改前缀时，同步重建前端镜像或自行挂载 `nginx.conf`。

### runtime 多副本

`runtime.replicaCount > 1` 时注意：

1. 前端 nginx 的 `upstream` 在启动时解析 `apboa-runtime`（ClusterIP），
   扩容后需要 `kubectl rollout restart deploy/apboa-frontend` 才能真正分流；
2. 跨 Pod 的会话亲和依赖 `X-Apboa-Thread-Id` 一致性哈希，而在 ClusterIP 后面
   连的是同一个 VIP，哈希退化为 kube-proxy 轮询。要严格亲和，需要 headless Service
   配合支持 `resolve` 的 nginx（1.27.3+）或改用 Ingress 的会话保持；
3. 多副本必须保证 `.apboa` 是同一份 RWX 存储，否则会出现数据分叉。

默认 `replicaCount: 1`，先把链路跑通再扩容。

## 6. 数据库初始化 / 升级

* 内置 MySQL：数据目录为空时自动执行 `files/db_init.sql`（内容取自 `sql/db_init.sql`）。
  改了 SQL 需要 `helm upgrade` 后**重建 PVC**才能重跑，生产不要这么干。
* 外部 MySQL：手工导入
  ```bash
  mysql -h <host> -u <user> -p <db> < sql/db_init.sql
  ```
* 后续增量脚本在 `sql/incremental/`，需要按版本手工执行，chart 不处理。

## 7. 升级与卸载

```bash
helm upgrade apboa ./deploy/helm/apboa -n apboa -f my-values.yaml
helm diff upgrade apboa ./deploy/helm/apboa -n apboa -f my-values.yaml   # 装 helm-diff 插件后

helm uninstall apboa -n apboa
```

* 密码 / JWT 通过 `lookup` 从既有 Secret 复用，`helm upgrade` 不会轮换（除非显式改 values）。
* `persistence.data.keep: true`（默认）会给数据 PVC 打 `helm.sh/resource-policy: keep`，
  卸载后 PVC 保留；**再次安装前需要先删掉同名 PVC**，否则会 `already exists` 报错。
* StatefulSet 的 `volumeClaimTemplates` 生成的 PVC 本来就不随 release 删除。

## 8. 排障

```bash
kubectl -n apboa get pods
kubectl -n apboa get pvc                  # Pending 多半是 RWX 存储不支持
kubectl -n apboa logs deploy/apboa-console --tail=100
kubectl -n apboa describe pod -l app.kubernetes.io/component=runtime
```

| 现象 | 排查方向 |
| --- | --- |
| Pod Pending | PVC 未 Bound（RWX 不可用）；hostNetwork 的 gateway 端口冲突；资源 requests 过大 |
| 前端 502 /api/ | 控制台 Service 名与 `nginx.conf` 里的 `apboa-console` 不一致 |
| 前端 502 /api/runtime/ | `RUNTIME_HOST` 指向错误；runtime 未就绪 |
| 登录报 401 / token 失效 | 多次重装导致 `JWT_SECRET` 变化 |
| 服务反复重启 | 中间件未就绪或密码与库中不一致（Secret 被重建） |
| gateway 端口不通 | 节点安全组 / NetworkPolicy 未放行；确认 `hostNetwork: true` |

## 9. 迁移自 compose 的检查清单

- [ ] 镜像已推送，`global.imageRegistry` 与各组件 tag 已对齐
- [ ] `external.*` 或内置中间件的连接信息与 compose `.env` 一致
- [ ] `.apboa` 共享存储：单节点 RWO / 多节点 RWX
- [ ] 资源 limits（尤其 memory）与 `*_MEM_LIMIT` 对齐，确认 JVM 堆比例合理
- [ ] 若原部署依赖 NFS，先在集群侧准备 RWX StorageClass，别用本地盘顶上
- [ ] gateway 所在节点放行应用端口，并确认节点端口未被占用
