{{/*
Labels common to every object's metadata.
Pod selector labels are deliberately NOT derived from these - they are the
fixed 'name: ta-authenticator' label (selectors are immutable on Deployments,
and a fixed name allows adoption of an existing installation).
*/}}
{{- define "ta-authenticator.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
The authenticator image tag, the chart's appVersion unless set.
*/}}
{{- define "ta-authenticator.imageTag" -}}
{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{/*
The authenticator image pull policy. An explicit policy is used if set,
otherwise mutable tags ('latest' and 'stable') are always pulled.
*/}}
{{- define "ta-authenticator.imagePullPolicy" -}}
{{- if .Values.image.pullPolicy -}}
{{ .Values.image.pullPolicy }}
{{- else if has (include "ta-authenticator.imageTag" .) (list "latest" "stable") -}}
Always
{{- else -}}
IfNotPresent
{{- end -}}
{{- end }}

{{/*
The Ingress class, which must be 'nginx' or 'traefik'.
*/}}
{{- define "ta-authenticator.ingressClassName" -}}
{{- $className := .Values.ingress.className -}}
{{- if not (has $className (list "nginx" "traefik")) -}}
{{- fail (printf "ingress.className must be 'nginx' or 'traefik' (got '%s')" $className) -}}
{{- end -}}
{{ $className }}
{{- end }}
