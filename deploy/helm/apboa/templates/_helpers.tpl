{{/*
基础名称：所有资源名前缀（默认 apboa）
*/}}
{{- define "apboa.name" -}}
{{- default "apboa" .Values.namePrefix | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{/*
某个组件的资源名：<prefix>-<component>
参数：dict "root" $ "component" "console"
*/}}
{{- define "apboa.resourceName" -}}
{{- printf "%s-%s" (include "apboa.name" .root) .component -}}
{{- end -}}

{{/*
通用标签
*/}}
{{- define "apboa.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "apboa.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: apboa
{{- end -}}

{{/*
选择器标签（不可变，禁止加入 version）
参数：dict "root" $ "component" "console"
*/}}
{{- define "apboa.selectorLabels" -}}
app.kubernetes.io/name: {{ include "apboa.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
完整镜像地址：<registry>/<repository>:<tag>
参数：dict "root" $ "component" (.Values.console 等)
*/}}
{{- define "apboa.image" -}}
{{- $registry := .root.Values.global.imageRegistry | default "" -}}
{{- $repo := .component.image.repository -}}
{{- if $registry -}}
{{- $repo = printf "%s/%s" (trimSuffix "/" $registry) $repo -}}
{{- end -}}
{{- printf "%s:%s" $repo (.component.image.tag | default "latest" | toString) -}}
{{- end -}}

{{/*
拉取策略
*/}}
{{- define "apboa.pullPolicy" -}}
{{- if .component.image.pullPolicy -}}
{{- .component.image.pullPolicy -}}
{{- else -}}
{{- .root.Values.global.imagePullPolicy -}}
{{- end -}}
{{- end -}}

{{/*
中间件地址解析：内置中间件用 Service 名，否则用 external.*
*/}}
{{- define "apboa.mysqlHost" -}}
{{- if .Values.middleware.mysql.enabled -}}
{{ include "apboa.name" . }}-mysql
{{- else -}}
{{- required "middleware.mysql.enabled=false 时必须设置 external.mysql.host" .Values.external.mysql.host -}}
{{- end -}}
{{- end -}}

{{- define "apboa.mysqlPort" -}}
{{- if .Values.middleware.mysql.enabled -}}3306{{- else -}}{{ .Values.external.mysql.port }}{{- end -}}
{{- end -}}

{{- define "apboa.mysqlDatabase" -}}
{{- if .Values.middleware.mysql.enabled -}}{{ .Values.middleware.mysql.auth.database }}{{- else -}}{{ .Values.external.mysql.database }}{{- end -}}
{{- end -}}

{{- define "apboa.mysqlUsername" -}}
{{- if .Values.middleware.mysql.enabled -}}{{ .Values.middleware.mysql.auth.username }}{{- else -}}{{ .Values.external.mysql.username }}{{- end -}}
{{- end -}}

{{- define "apboa.redisHost" -}}
{{- if .Values.middleware.redis.enabled -}}
{{ include "apboa.name" . }}-redis
{{- else -}}
{{- required "middleware.redis.enabled=false 时必须设置 external.redis.host" .Values.external.redis.host -}}
{{- end -}}
{{- end -}}

{{- define "apboa.redisPort" -}}
{{- if .Values.middleware.redis.enabled -}}6379{{- else -}}{{ .Values.external.redis.port }}{{- end -}}
{{- end -}}

{{- define "apboa.redisDatabase" -}}
{{- if .Values.middleware.redis.enabled -}}7{{- else -}}{{ .Values.external.redis.database }}{{- end -}}
{{- end -}}

{{- define "apboa.pgHost" -}}
{{- if .Values.middleware.pgvector.enabled -}}
{{ include "apboa.name" . }}-pgvector
{{- else -}}
{{- required "middleware.pgvector.enabled=false 时必须设置 external.pgvector.host" .Values.external.pgvector.host -}}
{{- end -}}
{{- end -}}

{{- define "apboa.pgPort" -}}
{{- if .Values.middleware.pgvector.enabled -}}5432{{- else -}}{{ .Values.external.pgvector.port }}{{- end -}}
{{- end -}}

{{- define "apboa.pgDatabase" -}}
{{- if .Values.middleware.pgvector.enabled -}}{{ .Values.middleware.pgvector.auth.database }}{{- else -}}{{ .Values.external.pgvector.database }}{{- end -}}
{{- end -}}

{{- define "apboa.pgUsername" -}}
{{- if .Values.middleware.pgvector.enabled -}}{{ .Values.middleware.pgvector.auth.username }}{{- else -}}{{ .Values.external.pgvector.username }}{{- end -}}
{{- end -}}

{{/*
Secret 名称
*/}}
{{- define "apboa.secretName" -}}
{{- printf "%s-secret" (include "apboa.name" .) -}}
{{- end -}}

{{/*
环境变量片段（供各 Deployment 引用）
*/}}
{{- define "apboa.envMysql" -}}
- name: MYSQL_HOST
  value: {{ include "apboa.mysqlHost" . | quote }}
- name: MYSQL_PORT
  value: {{ include "apboa.mysqlPort" . | quote }}
- name: MYSQL_DATABASE
  value: {{ include "apboa.mysqlDatabase" . | quote }}
- name: MYSQL_USER
  value: {{ include "apboa.mysqlUsername" . | quote }}
- name: MYSQL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "apboa.secretName" . }}
      key: MYSQL_PASSWORD
{{- end -}}

{{- define "apboa.envRedis" -}}
- name: REDIS_HOST
  value: {{ include "apboa.redisHost" . | quote }}
- name: REDIS_PORT
  value: {{ include "apboa.redisPort" . | quote }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "apboa.secretName" . }}
      key: REDIS_PASSWORD
- name: REDIS_DATABASE
  value: {{ include "apboa.redisDatabase" . | quote }}
{{- end -}}

{{- define "apboa.envPg" -}}
- name: VECTOR_STORE_TYPE
  value: {{ .Values.app.vectorStoreType | quote }}
- name: PG_HOST
  value: {{ include "apboa.pgHost" . | quote }}
- name: PG_PORT
  value: {{ include "apboa.pgPort" . | quote }}
- name: PG_DATABASE
  value: {{ include "apboa.pgDatabase" . | quote }}
- name: PG_USER
  value: {{ include "apboa.pgUsername" . | quote }}
- name: PG_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "apboa.secretName" . }}
      key: PG_PASSWORD
{{- end -}}

{{- define "apboa.envJwt" -}}
- name: JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "apboa.secretName" . }}
      key: JWT_SECRET
{{- end -}}

{{/*
心跳上报的节点标识：compose 中由 start-execute.sh 注入宿主机 IP；
K8s 用调度节点名，保证同一节点上的 runtime/proxy/gateway 拿到同一个 nodeId。
*/}}
{{- define "apboa.envNodeId" -}}
- name: APBOA_NODE_ID
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
{{- end -}}

{{/*
控制台地址（供心跳、文件同步使用）
*/}}
{{- define "apboa.consoleHost" -}}
{{- printf "%s-console" (include "apboa.name" .) -}}
{{- end -}}

{{/*
镜像拉取密钥
*/}}
{{- define "apboa.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets -}}
imagePullSecrets:
{{ toYaml . | indent 2 }}
{{- end -}}
{{- end -}}

{{/*
调度约束合并（全局 + 组件级）
参数：dict "root" $ "component" (.Values.console)
*/}}
{{- define "apboa.nodeSelector" -}}
{{- $sel := merge (deepCopy (.component.nodeSelector | default dict)) (.root.Values.global.nodeSelector | default dict) -}}
{{- with $sel -}}
nodeSelector:
{{ toYaml . | indent 2 }}
{{- end -}}
{{- end -}}

{{- define "apboa.tolerations" -}}
{{- $tol := .component.tolerations | default .root.Values.global.tolerations -}}
{{- with $tol -}}
tolerations:
{{ toYaml . | indent 2 }}
{{- end -}}
{{- end -}}

{{- define "apboa.affinity" -}}
{{- $aff := .component.affinity | default .root.Values.global.affinity -}}
{{- with $aff -}}
affinity:
{{ toYaml . | indent 2 }}
{{- end -}}
{{- end -}}

{{/*
Pod 安全上下文（fsGroup 可选）
*/}}
{{- define "apboa.podSecurityContext" -}}
{{- if .Values.securityContext.fsGroup -}}
securityContext:
  fsGroup: {{ .Values.securityContext.fsGroup }}
{{- end -}}
{{- end -}}
