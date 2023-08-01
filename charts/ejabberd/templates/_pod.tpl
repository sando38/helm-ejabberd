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
            echo "> initContainer to copy k8s secrets to cert directory ..." ;
            secrets="$(cd /tmp/certs ; ls */ -d | sed -e 's|/||')" ;
            for secret in $secrets ;
            do
              files="$(cd /tmp/certs/$secret ; ls *)" ;
              for file in $files ;
              do
                echo ">> copy $secret/$file to /opt/ejabberd/certs" ;
                name="namespace_$POD_NAMESPACE.secret_$secret.$file" ;
                cp /tmp/certs/$secret/$file /opt/ejabberd/certs/$name ;
              done ;
            done ;
            echo ">> copying complete!"
        volumeMounts:
          - name: {{ include "ejabberd.fullname" . }}-certs
            mountPath: /opt/ejabberd/certs
        {{- range $name := .Values.certFiles.secretName }}
          - name: ejabberd-certs-{{ $name | replace "." "-" }}
            mountPath: /tmp/certs/{{ $name }}
        {{- end }}
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
      - name: cert-watcher
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
        env:
        - name: LABEL
          value: "helm-ejabberd/tls-certificate"
        - name: LABEL_VALUE
          value: "true"
        - name: FOLDER
          value: /opt/ejabberd/certs
        - name: RESOURCE
          value: secret
        - name: NAMESPACE
          value: {{ template "ejabberd.namespace" . }}
        - name: UNIQUE_FILENAMES
          value: "true"
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
