{{- define "osmo-secrets.sync-container" -}}
- name: sync
  image: {{ .Values.image.repository }}:{{ .Values.image.tag | quote }}
  env:
    - name: SECRET_ARN
      value: {{ .Values.secretArn | quote }}
    - name: AWS_REGION
      value: {{ .Values.awsRegion | quote }}
    - name: NAMESPACE
      value: {{ .Release.Namespace | quote }}
    - name: KUBECTL_VERSION
      value: {{ .Values.kubectlVersion | quote }}
  command:
    - /bin/bash
    - -c
    - |
      set -euo pipefail
      curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
      curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
      echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check --strict
      chmod +x kubectl && mv kubectl /usr/local/bin/

      SECRET_JSON=$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_ARN" \
        --region "$AWS_REGION" \
        --query SecretString --output text)

      DB_USER=$(python3 -c "import sys,json; print(json.load(sys.stdin)['username'])" <<< "$SECRET_JSON")
      DB_PASS=$(python3 -c "import sys,json; print(json.load(sys.stdin)['password'])" <<< "$SECRET_JSON")

      kubectl create secret generic db-secret \
        --namespace "$NAMESPACE" \
        --from-literal=db-user="$DB_USER" \
        --from-literal=db-password="$DB_PASS" \
        --dry-run=client -o yaml | kubectl apply -f -
{{- end -}}
