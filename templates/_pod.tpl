{{- define "ejabberd.podTemplate" }}
    metadata:
      annotations:
      {{- with .Values.podAnnotations }}
      {{- toYaml . | nindent 8 }}
      {{- end }}
      labels:
      {{- include "ejabberd.labels" . | nindent 8 -}}
      {{- with .Values.podLabels }}
      {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "ejabberd.serviceAccountName" . }}
      terminationGracePeriodSeconds: {{ default 60 .Values.statefulSet.terminationGracePeriodSeconds }}
      hostNetwork: {{ .Values.hostNetwork }}
      {{- with .Values.statefulSet.dnsPolicy }}
      dnsPolicy: {{ . }}
      {{- end }}
      {{- with .Values.statefulSet.dnsConfig }}
      dnsConfig:
        {{- if .searches }}
        searches:
          {{- toYaml .searches | nindent 10 }}
        {{- end }}
        {{- if .nameservers }}
        nameservers:
          {{- toYaml .nameservers | nindent 10 }}
        {{- end }}
        {{- if .options }}
        options:
          {{- toYaml .options | nindent 10 }}
        {{- end }}
      {{- end }}
      {{- with .Values.statefulSet.initContainers }}
      initContainers:
      {{- toYaml . | nindent 6 }}
      {{- end }}
      {{- if .Values.statefulSet.shareProcessNamespace }}
      shareProcessNamespace: true
      {{- end }}
      containers:
      - image: {{ template "ejabberd.image-name" . }}
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        name: {{ template "ejabberd.fullname" . }}
        resources:
          {{- with .Values.resources }}
          {{- toYaml . | nindent 10 }}
          {{- end }}
        readinessProbe:
          tcpSocket:
            port: {{ .Values.listen.c2s.port }}
          initialDelaySeconds: 10
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: {{ .Values.listen.c2s.port }}
          initialDelaySeconds: 10
          periodSeconds: 10
        lifecycle:
          {{- with .Values.statefulSet.lifecycle }}
          {{- toYaml . | nindent 10 }}
          {{- end }}
        ports:
        {{- $hostNetwork := .Values.hostNetwork }}
        {{- range $name, $config := .Values.listen }}
        {{- if $config }}
          {{- if and $hostNetwork (and $config.hostPort $config.port) }}
            {{- if ne ($config.hostPort | int) ($config.port | int) }}
              {{- fail "ERROR: All hostPort must match their respective containerPort when `hostNetwork` is enabled" }}
            {{- end }}
          {{- end }}
        - name: {{ $name | quote }}
          containerPort: {{ default $config.port $config.containerPort }}
          {{- if $config.hostPort }}
          hostPort: {{ $config.hostPort }}
          {{- end }}
          {{- if $config.hostIP }}
          hostIP: {{ $config.hostIP }}
          {{- end }}
          protocol: {{ default "TCP" $config.protocol | quote }}
        {{- if $config.http3 }}
        {{- if and $config.http3.enabled $config.hostPort }}
        {{- $http3Port := default $config.hostPort $config.http3.advertisedPort }}
        - name: "{{ $name }}-http3"
          containerPort: {{ $config.port }}
          hostPort: {{ $http3Port }}
          protocol: UDP
        {{- end }}
        {{- end }}
        {{- end }}
        {{- end }}
        {{- with .Values.securityContext }}
        securityContext:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        volumeMounts:
          - name: {{ include "ejabberd.fullname" . }}-certs
            mountPath: {{ .Values.certFiles.path }}
            readOnly: true
          - name: mnesia
            mountPath: /opt/ejabberd/database
          - name: {{ include "ejabberd.fullname" . }}-config
            mountPath: /opt/ejabberd/conf/ejabberd.yml
            subPath: ejabberd.yml
          {{- $root := . }}
          {{- range .Values.volumes }}
          - name: {{ tpl (.name) $root | replace "." "-" }}
            mountPath: {{ .mountPath }}
            readOnly: true
          {{- end }}
          {{- if .Values.additionalVolumeMounts }}
            {{- toYaml .Values.additionalVolumeMounts | nindent 10 }}
          {{- end }}
        args:
          {{- with .Values.globalArguments }}
          {{- range . }}
          - {{ . | quote }}
          {{- end }}
          {{- end }}
          {{- with .Values.additionalArguments }}
          {{- range . }}
          - {{ . | quote }}
          {{- end }}
          {{- end }}
        {{- with .Values.env }}
        env:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- with .Values.envFrom }}
        envFrom:
          {{- toYaml . | nindent 10 }}
        {{- end }}
      {{- if .Values.statefulSet.additionalContainers }}
        {{- toYaml .Values.statefulSet.additionalContainers | nindent 6 }}
      {{- end }}
      volumes:
        - name: {{ include "ejabberd.fullname" . }}-certs
          secret:
            secretName: {{ .Values.certFiles.secretName }}
        - name: tmp
          emptyDir: {}
        - name: {{ include "ejabberd.fullname" . }}-config
          configMap:
            name: {{ include "ejabberd.fullname" . }}-config
            items:
            - key: ejabberd.yml
              path: ejabberd.yml
        {{- $root := . }}
        {{- range .Values.volumes }}
        - name: {{ tpl (.name) $root | replace "." "-" }}
          {{- if eq .type "secret" }}
          secret:
            secretName: {{ tpl (.name) $root }}
          {{- else if eq .type "configMap" }}
          configMap:
            name: {{ tpl (.name) $root }}
          {{- end }}
        {{- end }}
        {{- if .Values.statefulSet.additionalVolumes }}
          {{- toYaml .Values.statefulSet.additionalVolumes | nindent 8 }}
        {{- end }}
      {{- if .Values.affinity }}
      affinity:
        {{- tpl (toYaml .Values.affinity) . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if .Values.priorityClassName }}
      priorityClassName: {{ .Values.priorityClassName }}
      {{- end }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if .Values.topologySpreadConstraints }}
      {{- if (semverCompare "<1.19.0-0" .Capabilities.KubeVersion.Version) }}
        {{- fail "ERROR: topologySpreadConstraints are supported only on kubernetes >= v1.19" -}}
      {{- end }}
      topologySpreadConstraints:
        {{- tpl (toYaml .Values.topologySpreadConstraints) . | nindent 8 }}
      {{- end }}
{{ end -}}
