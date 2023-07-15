{{- define "ejabberd.service-metadata" }}
  labels:
  {{- include "ejabberd.labels" . | nindent 4 -}}
  {{- with .Values.service.labels }}
  {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}

{{- define "ejabberd.service-spec" -}}
  {{- $type := default "LoadBalancer" .Values.service.type }}
  type: {{ $type }}
  {{- with .Values.service.loadBalancerClass }}
  loadBalancerClass: {{ . }}
  {{- end}}
  {{- with .Values.service.spec }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
  selector:
    {{- include "ejabberd.selectorLabels" . | nindent 4 }}
  {{- if eq $type "LoadBalancer" }}
  {{- with .Values.service.loadBalancerSourceRanges }}
  loadBalancerSourceRanges:
  {{- toYaml . | nindent 2 }}
  {{- end -}}
  {{- end -}}
  {{- with .Values.service.externalIPs }}
  externalIPs:
  {{- toYaml . | nindent 2 }}
  {{- end -}}
  {{- with .Values.service.ipFamilyPolicy }}
  ipFamilyPolicy: {{ . }}
  {{- end }}
  {{- with .Values.service.ipFamilies }}
  ipFamilies:
  {{- toYaml . | nindent 2 }}
  {{- end -}}
{{- end }}

{{- define "ejabberd.service-ports" }}
  {{- range $name, $config := . }}
  {{- if $config.enabled }}
  {{- if $config.expose }}
  - port: {{ default $config.port $config.exposedPort }}
    name: {{ $name | quote }}
    targetPort: {{ default $name $config.targetPort }}
    protocol: {{ default "TCP" $config.protocol }}
    {{- if $config.nodePort }}
    nodePort: {{ $config.nodePort }}
    {{- end }}
    {{- if $config.appProtocol }}
    appProtocol: {{ $config.appProtocol }}
    {{- end }}
  {{- end }}
  {{- end }}
  {{- end }}
{{- end }}
