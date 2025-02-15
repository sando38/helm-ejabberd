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
      {{- if .Values.certFiles.sideCar.nativeSidecar }}
      {{ template "ejabberd.sideCarTemplate" . }}
        restartPolicy: Always
      {{- else }}
      - name: init-copy-certs
        image: docker.io/library/alpine:3.19.1
        imagePullPolicy: Always
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsUser: 9000
          runAsGroup: 9000
          runAsNonRoot: true
          privileged: false
          capabilities:
            drop: [ALL]
          seccompProfile:
            type: RuntimeDefault
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
        command: ["/sbin/tini","--", "/bin/sh", "-c", "run.sh"]
        startupProbe:
          {{- if .Values.statefulSet.startupProbe }}
          {{- toYaml .Values.statefulSet.startupProbe | nindent 10 }}
          {{- else }}
          exec:
            command:
            - cat
            - /opt/ejabberd/.ejabberd_ready
          failureThreshold: 10
          periodSeconds: 3
          {{- end }}
        readinessProbe:
          {{- if .Values.statefulSet.readinessProbe }}
          {{- toYaml .Values.statefulSet.readinessProbe | nindent 10 }}
          {{- else }}
          exec:
            command:
            - cat
            - /opt/ejabberd/.ejabberd_ready
          periodSeconds: 3
          {{- end }}
        livenessProbe:
          {{- if .Values.statefulSet.livenessProbe }}
          {{- toYaml .Values.statefulSet.livenessProbe | nindent 10 }}
          {{- else }}
          exec:
            command:
            - cat
            - /opt/ejabberd/.ejabberd_ready
          periodSeconds: 3
          failureThreshold: 30
          terminationGracePeriodSeconds: 5
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
        - name: "tcp-erl-dist"
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
          - name: {{ include "ejabberd.fullname" . }}-startup-scripts
            mountPath: /usr/local/bin/ejabberdctl
            subPath: ejabberdctl
            readOnly: true
          - name: {{ include "ejabberd.fullname" . }}-startup-scripts
            mountPath: /usr/local/bin/run.sh
            subPath: run.sh
            readOnly: true
        {{- if (eq (toString .Values.sqlDatabase.config.sql_type) "mssql") }}
          - name: tmpfs
            mountPath: /tmp/ejabberd
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
        env:
          - name: K8S_CLUSTERING
            value: "true"
          - name: POD_NAMESPACE
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace
          - name: ELECTOR_ENABLED
            value: "{{ default "true" .Values.elector.enabled }}"
          - name: ELECTION_NAME
            value: "{{ default "ejabberd" .Values.elector.name }}"
          - name: ELECTION_URL
            value: "{{ default "127.0.0.1:4040" .Values.elector.url }}"
          - name: ERLANG_COOKIE
            {{- if and .Values.erlangCookie.secretName .Values.erlangCookie.secretKey }}
            valueFrom:
              secretKeyRef:
                name: {{ .Values.erlangCookie.secretName }}
                key: {{ .Values.erlangCookie.secretKey }}
            {{- else }}
            value: {{ .Values.erlangCookie.value }}
            {{- end }}
          - name: HTTP_API_URL
            value: "{{ default "127.0.0.1" .Values.certFiles.sideCar.apiAddress }}:{{ default 5281 .Values.certFiles.sideCar.apiPort }}"
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
      {{- if not .Values.certFiles.sideCar.nativeSidecar }}
      {{ template "ejabberd.sideCarTemplate" . }}
      {{- end }}
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
        {{- if (eq (toString .Values.sqlDatabase.config.sql_type) "mssql") }}
        - name: tmpfs
          emptyDir: {}
        {{- end }}
        - name: {{ include "ejabberd.fullname" . }}-startup-scripts
          configMap:
            name: {{ include "ejabberd.fullname" . }}-startup-scripts
            defaultMode: 0755
            items:
            - key: run.sh
              path: run.sh
            - key: ejabberdctl
              path: ejabberdctl
        {{- if .Values.volumes }}
          {{- toYaml .Values.volumes | nindent 8 }}
        {{- end }}
        {{- if .Values.statefulSet.additionalVolumes }}
          {{- toYaml .Values.statefulSet.additionalVolumes | nindent 8 }}
        {{- end }}
{{ end -}}
