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
          {{- if .Values.statefulSet.readinessProbe }}
          {{- toYaml .Values.statefulSet.readinessProbe | nindent 10 }}
          {{- else }}
          tcpSocket:
            port: {{ default .Values.listen.c2s.port .Values.healthCheck.tcpPort }}
          initialDelaySeconds: 10
          periodSeconds: 10
          {{- end }}
        livenessProbe:
          {{- if .Values.statefulSet.livenessProbe }}
          {{- toYaml .Values.statefulSet.livenessProbe | nindent 10 }}
          {{- else }}
          tcpSocket:
            port:  {{ default .Values.listen.c2s.port .Values.healthCheck.tcpPort }}
          initialDelaySeconds: 10
          periodSeconds: 10
          {{- end }}
        lifecycle:
          {{- with .Values.statefulSet.lifecycle }}
          {{- toYaml . | nindent 10 }}
          {{- end }}
        ports:
        {{- $hostNetwork := .Values.hostNetwork }}
        {{- range $name, $config := .Values.listen }}
        {{- if $config }}
        {{- if $config.enabled }}
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
        {{- end }}
        {{- end }}
        {{- end }}
        {{- if .Values.service.headless }}
        - name: "erl-dist-port"
          containerPort: {{ default 5210 .Values.service.headless.erlDistPort }}
          protocol: "TCP"
        {{- end }}
        {{- with .Values.securityContext }}
        securityContext:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        volumeMounts:
        {{- range $name := .Values.certFiles.secretName }}
          - name: ejabberd-certs-{{ $name }}
            mountPath: /opt/ejabberd/certs/{{ $name }}
            readOnly: true
        {{- end }}
          - name: mnesia
            mountPath: /opt/ejabberd/database
          - name: {{ include "ejabberd.fullname" . }}-config
            mountPath: /opt/ejabberd/conf/ejabberd.yml
            subPath: ejabberd.yml
          - name: {{ include "ejabberd.fullname" . }}-config
            mountPath: /opt/ejabberd/conf/modules-default.yml
            subPath: modules-default.yml
          - name: {{ include "ejabberd.fullname" . }}-config
            mountPath: /opt/ejabberd/conf/shaper.yml
            subPath: shaper.yml
          - name: {{ include "ejabberd.fullname" . }}-config
            mountPath: /opt/ejabberd/conf/shaper-rules.yml
            subPath: shaper-rules.yml
          - name: {{ include "ejabberd.fullname" . }}-config
            mountPath: /opt/ejabberd/conf/acl.yml
            subPath: acl.yml
          - name: {{ include "ejabberd.fullname" . }}-config
            mountPath: /opt/ejabberd/conf/api-permissions.yml
            subPath: api-permissions.yml
          - name: {{ include "ejabberd.fullname" . }}-config
            mountPath: /opt/ejabberd/conf/access-rules.yml
            subPath: access-rules.yml
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
        env:
          - name: ERLANG_COOKIE
            value: {{ default "erlangCookie" .Values.erlangCookie }}
        {{- if .Values.service.headless }}
          - name: ERL_DIST_PORT
            value: {{ default 5210 .Values.service.headless.erlDistPort | quote }}
        {{- end }}
        {{- with .Values.env }}
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- with .Values.envFrom }}
        envFrom:
          {{- toYaml . | nindent 10 }}
        {{- end }}
      {{- if .Values.statefulSet.additionalContainers }}
        {{- toYaml .Values.statefulSet.additionalContainers | nindent 6 }}
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
      volumes:
        {{- range $name := .Values.certFiles.secretName }}
        - name: ejabberd-certs-{{ $name }}
          secret:
            secretName: {{ $name }}
        {{- end }}
        - name: tmp
          emptyDir: {}
        - name: {{ include "ejabberd.fullname" . }}-config
          configMap:
            name: {{ include "ejabberd.fullname" . }}-config
            items:
            - key: ejabberd.yml
              path: ejabberd.yml
            - key: modules-default.yml
              path: modules-default.yml
            - key: shaper.yml
              path: shaper.yml
            - key: shaper-rules.yml
              path: shaper-rules.yml
            - key: acl.yml
              path: acl.yml
            - key: api-permissions.yml
              path: api-permissions.yml
            - key: access-rules.yml
              path: access-rules.yml
        {{- if .Values.volumes }}
          {{- toYaml .Values.volumes | nindent 8 }}
        {{- end }}
        {{- if .Values.statefulSet.additionalVolumes }}
          {{- toYaml .Values.statefulSet.additionalVolumes | nindent 8 }}
        {{- end }}
{{ end -}}
