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
      {{- if or .Values.statefulSet.initContainers .Values.certFiles.sideCar.enabled }}
      initContainers:
      {{- if .Values.certFiles.sideCar.enabled }}
      - name: init-copy-certs
        image: docker.io/library/busybox:latest
        imagePullPolicy: IfNotPresent
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsUser: 9000
          runAsGroup: 9000
          runAsNonRoot: true
          privileged: false
          capabilities:
            drop: [ALL]
        env:
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        command: ["/bin/sh", "-c"]
        args:
          - >-
            set -e ;
            set -u ;
            echo "> initContainer to copy configmap & secrets ..." ;
            echo ">> Copy config files to /opt/ejabberd/conf" ;
            cp /tmp/conf/* /opt/ejabberd/conf ;
            echo ">> Copying config files complete!" ;
            echo ">> Copy TLS certs to /opt/ejabberd/certs" ;
            cp -r /tmp/certs/* /opt/ejabberd/certs ;
            echo ">> Copying TLS certs complete!"
        volumeMounts:
          - name: {{ include "ejabberd.fullname" . }}-certs
            mountPath: /opt/ejabberd/certs
        {{- range $name := .Values.certFiles.secretName }}
          - name: ejabberd-certs-{{ $name | replace "." "-" }}
            mountPath: /tmp/certs/{{ $name }}
        {{- end }}
          - name: {{ include "ejabberd.fullname" . }}-config
            mountPath: /opt/ejabberd/conf
          - name: {{ include "ejabberd.fullname" . }}-configfiles
            mountPath: /tmp/conf
      {{- end }}
      {{- with .Values.statefulSet.initContainers }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
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
          {{- if .Values.certFiles.sideCar.enabled }}
          initialDelaySeconds: {{ default 10 .Values.certFiles.sideCar.waitPeriod }}
          {{- else }}
          initialDelaySeconds: 10
          {{- end }}
          periodSeconds: 15
          {{- end }}
        livenessProbe:
          {{- if .Values.statefulSet.livenessProbe }}
          {{- toYaml .Values.statefulSet.livenessProbe | nindent 10 }}
          {{- else }}
          tcpSocket:
            port:  {{ default .Values.listen.c2s.port .Values.healthCheck.tcpPort }}
          {{- if .Values.certFiles.sideCar.enabled }}
          initialDelaySeconds: {{ default 10 .Values.certFiles.sideCar.waitPeriod }}
          {{- else }}
          initialDelaySeconds: 10
          {{- end }}
          periodSeconds: 15
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
        {{- if .Values.certFiles.sideCar.enabled }}
          - name: {{ include "ejabberd.fullname" . }}-certs
            mountPath: /opt/ejabberd/certs
            readOnly: true
        {{- else }}
        {{- range $name := .Values.certFiles.secretName }}
          - name: ejabberd-certs-{{ $name | replace "." "-" }}
            mountPath: /opt/ejabberd/certs/{{ $name }}
            readOnly: true
        {{- end }}
        {{- end }}
          - name: mnesia
            mountPath: /opt/ejabberd/database
          - name: {{ include "ejabberd.fullname" . }}-config
            mountPath: /opt/ejabberd/conf
            #readOnly: true
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
        {{- if .Values.certFiles.sideCar.enabled }}
          - name: WAIT_PERIOD
            value: {{ default 0 .Values.certFiles.sideCar.waitPeriod | quote }}
        {{- end }}
        {{- with .Values.env }}
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- with .Values.envFrom }}
        envFrom:
          {{- toYaml . | nindent 10 }}
        {{- end }}
      {{- if .Values.certFiles.sideCar.enabled }}
      - name: watcher
        image: kiwigrid/k8s-sidecar:latest
        imagePullPolicy: IfNotPresent
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsUser: 9000
          runAsGroup: 9000
          runAsNonRoot: true
          privileged: false
          capabilities:
            drop: [ALL]
        volumeMounts:
        - name: {{ include "ejabberd.fullname" . }}-certs
          mountPath: /opt/ejabberd/certs
        - name: {{ include "ejabberd.fullname" . }}-config
          mountPath: /opt/ejabberd/conf
        env:
        - name: LABEL
          value: "helm-ejabberd/watcher"
        - name: LABEL_VALUE
          value: "true"
        - name: FOLDER
          value: /opt/ejabberd
        - name: RESOURCE
          value: both
        - name: NAMESPACE
          value: {{ template "ejabberd.namespace" . }}
        #- name: UNIQUE_FILENAMES
        #  value: "true"
        - name: REQ_URL
          value: "http://{{ default "127.0.0.1" .Values.certFiles.sideCar.apiAddress }}:{{ default 5281 .Values.certFiles.sideCar.apiPort }}/api/{{ default "reload_config" .Values.certFiles.sideCar.apiCmd }}"
        - name: REQ_METHOD
          value: "{{ default "POST" .Values.certFiles.sideCar.apiMethod }}"
        - name: REQ_PAYLOAD
          value: "{{ default "{}" .Values.certFiles.sideCar.apiPayload }}"
        - name: REQ_RETRY_TOTAL
          value: {{ default 5 .Values.certFiles.sideCar.apiRetry | quote }}
        resources:
          limits:
            cpu: 500m
            memory: 500Mi
          requests:
            cpu: 100m
            memory: 128Mi
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
        {{- if .Values.certFiles.sideCar.enabled }}
        - name: {{ include "ejabberd.fullname" . }}-certs
          emptyDir: {}
        {{- end }}
        {{- range $name := .Values.certFiles.secretName }}
        - name: ejabberd-certs-{{ $name | replace "." "-" }}
          secret:
            secretName: {{ $name }}
        {{- end }}
        {{- if .Values.certFiles.sideCar.enabled }}
        - name: {{ include "ejabberd.fullname" . }}-config
          emptyDir: {}
        - name: {{ include "ejabberd.fullname" . }}-configfiles
          configMap:
            name: {{ include "ejabberd.fullname" . }}-config
        {{- else }}
        - name: {{ include "ejabberd.fullname" . }}-config
          configMap:
            name: {{ include "ejabberd.fullname" . }}-config
        {{- end }}
        {{- if .Values.volumes }}
          {{- toYaml .Values.volumes | nindent 8 }}
        {{- end }}
        {{- if .Values.statefulSet.additionalVolumes }}
          {{- toYaml .Values.statefulSet.additionalVolumes | nindent 8 }}
        {{- end }}
{{ end -}}
