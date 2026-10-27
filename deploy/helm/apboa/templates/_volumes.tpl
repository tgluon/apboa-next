{{/*
卷定义：所有使用 .apboa / /opt/tools / 日志目录的 Pod 共享同一套声明
*/}}

{{/* ---------- .apboa 共享目录 ---------- */}}
{{- define "apboa.dataVolume" -}}
- name: data
  {{- if .Values.persistence.data.existingClaim }}
  persistentVolumeClaim:
    claimName: {{ .Values.persistence.data.existingClaim }}
  {{- else if .Values.persistence.data.enabled }}
  persistentVolumeClaim:
    claimName: {{ include "apboa.name" . }}-data
  {{- else }}
  emptyDir: {}
  {{- end }}
{{- end -}}

{{- define "apboa.dataVolumeMount" -}}
- name: data
  mountPath: /app/.apboa
{{- end -}}

{{/* ---------- /opt/tools 依赖安装目录（按组件分子目录） ---------- */}}
{{- define "apboa.toolsVolume" -}}
- name: tools
  {{- if .Values.persistence.tools.existingClaim }}
  persistentVolumeClaim:
    claimName: {{ .Values.persistence.tools.existingClaim }}
  {{- else if .Values.persistence.tools.enabled }}
  persistentVolumeClaim:
    claimName: {{ include "apboa.name" . }}-tools
  {{- else }}
  emptyDir: {}
  {{- end }}
{{- end -}}

{{- define "apboa.toolsVolumeMount" -}}
- name: tools
  mountPath: /opt/tools
  {{- if or .root.Values.persistence.tools.existingClaim .root.Values.persistence.tools.enabled }}
  subPath: {{ .component }}
  {{- end }}
{{- end -}}

{{/* ---------- 日志目录 ---------- */}}
{{- define "apboa.logsVolume" -}}
{{- if .Values.persistence.logs.enabled }}
- name: logs
  {{- if .Values.persistence.logs.existingClaim }}
  persistentVolumeClaim:
    claimName: {{ .Values.persistence.logs.existingClaim }}
  {{- else }}
  persistentVolumeClaim:
    claimName: {{ include "apboa.name" . }}-logs
  {{- end }}
{{- else }}
- name: logs
  emptyDir: {}
{{- end }}
{{- end -}}

{{- define "apboa.logsVolumeMount" -}}
- name: logs
  mountPath: {{ .path | default "/app/logs" }}
  {{- if .root.Values.persistence.logs.enabled }}
  # 按组件分目录，避免各服务日志互相覆盖
  subPath: {{ .component }}
  {{- end }}
{{- end -}}
