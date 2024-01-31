{{- define "ejabberd.sideCarTemplate" }}
      - name: watcher
        image: {{ .Values.certFiles.sideCar.image }}
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
          value: {{ default 10 .Values.certFiles.sideCar.apiRetry | quote }}
        resources:
          limits:
            cpu: 500m
            memory: 500Mi
          requests:
            cpu: 100m
            memory: 128Mi
{{ end -}}
