{{/*
Labels common to every object's metadata.
Pod selector labels are deliberately NOT derived from these - they are the
fixed 'name: <object>' labels (selectors are immutable on StatefulSets and
Deployments, and fixed names allow adoption of existing installations).
*/}}
{{- define "fragalysis-stack.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
The stack image (used by the stack, worker and beat). A tag is required.
*/}}
{{- define "fragalysis-stack.stackImage" -}}
{{- $image := .Values.stack.image -}}
{{- $tag := required "stack.image.tag must be set" $image.tag -}}
{{ $image.registry }}/{{ $image.repository }}:{{ $tag }}
{{- end }}

{{/*
The stack image pull policy. An explicit policy is used if set,
otherwise mutable tags ('latest' and 'stable') are always pulled.
*/}}
{{- define "fragalysis-stack.stackImagePullPolicy" -}}
{{- $image := .Values.stack.image -}}
{{- if $image.pullPolicy -}}
{{ $image.pullPolicy }}
{{- else if has $image.tag (list "latest" "stable") -}}
Always
{{- else -}}
IfNotPresent
{{- end -}}
{{- end }}

{{/*
The host the application uses to connect to the database:
an external database, pgBouncer, or the database deployed by this chart.
*/}}
{{- define "fragalysis-stack.databaseHost" -}}
{{- if .Values.database.host -}}
{{ .Values.database.host }}
{{- else if .Values.pgbouncer.enabled -}}
pgbouncer
{{- else -}}
database
{{- end -}}
{{- end }}

{{/*
An init container that waits until a host can be resolved.
Expects a dict with 'registry', 'name' and 'host'.
*/}}
{{- define "fragalysis-stack.waitForContainer" -}}
- name: wait-for-{{ .name }}
  image: {{ .registry }}/library/busybox:1.28.0
  command:
  - sh
  - -c
  - {{ printf "until nslookup %s; do echo waiting for %s; sleep 1; done;" .host .name | quote }}
  terminationMessagePolicy: FallbackToLogsOnError
{{- end }}

{{/*
Node affinity - prefer 'core' before 'application' nodes,
then anything other than 'worker' before finally trying 'worker'.
*/}}
{{- define "fragalysis-stack.affinityCoreFirst" -}}
nodeAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 40
    preference:
      matchExpressions:
      - key: informaticsmatters.com/purpose-core
        operator: Exists
  - weight: 30
    preference:
      matchExpressions:
      - key: informaticsmatters.com/purpose-application
        operator: Exists
  - weight: 20
    preference:
      matchExpressions:
      - key: informaticsmatters.com/purpose-worker
        operator: DoesNotExist
{{- end }}

{{/*
Node affinity - prefer 'application' before 'core' nodes,
then anything other than 'worker' before finally trying 'worker'.
*/}}
{{- define "fragalysis-stack.affinityApplicationFirst" -}}
nodeAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 40
    preference:
      matchExpressions:
      - key: informaticsmatters.com/purpose-application
        operator: Exists
  - weight: 30
    preference:
      matchExpressions:
      - key: informaticsmatters.com/purpose-core
        operator: Exists
  - weight: 20
    preference:
      matchExpressions:
      - key: informaticsmatters.com/purpose-worker
        operator: DoesNotExist
{{- end }}

{{/*
Node affinity - a 'preferred' (not guaranteed) 'application' node.
*/}}
{{- define "fragalysis-stack.affinityApplication" -}}
nodeAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 40
    preference:
      matchExpressions:
      - key: informaticsmatters.com/purpose-application
        operator: Exists
{{- end }}

{{/*
Environment common to the stack, worker and beat containers:
celery, django and database material.
*/}}
{{- define "fragalysis-stack.commonEnv" -}}
- name: CELERY_BROKER_URL
  value: redis://redis:6379/0
- name: CELERY_RESULT_BACKEND
  value: redis://redis:6379/0
- name: DEPLOYMENT_MODE
  value: {{ .Values.stack.deploymentMode | quote }}
- name: WEB_DJANGO_SUPERUSER_NAME
  value: admin
- name: WEB_DJANGO_SUPERUSER_EMAIL
  value: noone@example.com
- name: WEB_DJANGO_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: django
      key: secret_key
- name: WEB_DJANGO_SUPERUSER_PASSWORD
  valueFrom:
    secretKeyRef:
      name: django
      key: superuser_password
- name: POSTGRESQL_DATABASE
  value: frag
- name: POSTGRESQL_USER
  value: fragalysis
- name: POSTGRESQL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: database
      key: user_password
- name: POSTGRESQL_HOST
  value: {{ include "fragalysis-stack.databaseHost" . | quote }}
- name: POSTGRESQL_PORT
  value: "5432"
- name: TMPDIR
  value: /tmp
{{- end }}

{{/*
Environment common to the stack and worker containers.
*/}}
{{- define "fragalysis-stack.applicationEnv" -}}
- name: NEO4J_BOLT_URL
  value: {{ printf "bolt://neo4j:test@%s:7687" .Values.graph.hostname | quote }}
- name: NEO4J_QUERY
  value: {{ .Values.graph.hostname | quote }}
- name: NEO4J_AUTH
  value: {{ printf "neo4j/%s" .Values.graph.password | quote }}
{{- with .Values.stack.sentryDsn }}
- name: FRAGALYSIS_BACKEND_SENTRY_DNS
  value: {{ . | quote }}
{{- end }}
{{- if .Values.oidc.rpClientSecret }}
- name: OIDC_RP_CLIENT_SECRET
  value: {{ .Values.oidc.rpClientSecret | quote }}
- name: OIDC_RP_CLIENT_ID
  value: {{ .Values.oidc.rpClientId | quote }}
- name: OIDC_KEYCLOAK_REALM
  value: {{ .Values.oidc.keycloakRealmUrl | quote }}
- name: OIDC_OP_LOGOUT_URL_METHOD
  value: {{ .Values.oidc.opLogoutUrlMethod | quote }}
- name: OIDC_RENEW_ID_TOKEN_EXPIRY_MINUTES
  value: {{ .Values.oidc.renewIdTokenExpiryMinutes | quote }}
{{- end }}
{{- with .Values.oidc.asClientId }}
- name: OIDC_AS_CLIENT_ID
  value: {{ . | quote }}
{{- end }}
{{- with .Values.oidc.dmClientId }}
- name: OIDC_DM_CLIENT_ID
  value: {{ . | quote }}
{{- end }}
{{- if .Values.stack.debug }}
- name: DEBUG_FRAGALYSIS
  value: "True"
{{- end }}
{{- with .Values.squonk2.dmapiUrl }}
- name: SQUONK2_DMAPI_URL
  value: {{ . | quote }}
{{- end }}
{{- with .Values.squonk2.asapiUrl }}
- name: SQUONK2_ASAPI_URL
  value: {{ . | quote }}
{{- end }}
{{- with .Values.squonk2.uiUrl }}
- name: SQUONK2_UI_URL
  value: {{ . | quote }}
{{- end }}
{{- with .Values.squonk2.orgOwner }}
- name: SQUONK2_ORG_OWNER
  value: {{ . | quote }}
{{- end }}
{{- with .Values.squonk2.orgOwnerPassword }}
- name: SQUONK2_ORG_OWNER_PASSWORD
  value: {{ . | quote }}
{{- end }}
{{- with .Values.squonk2.orgUuid }}
- name: SQUONK2_ORG_UUID
  value: {{ . | quote }}
{{- end }}
{{- with .Values.squonk2.productFlavour }}
- name: SQUONK2_PRODUCT_FLAVOUR
  value: {{ . | quote }}
{{- end }}
{{- with .Values.squonk2.slug }}
- name: SQUONK2_SLUG
  value: {{ . | quote }}
{{- end }}
{{- with .Values.squonk2.unitBillingDay }}
- name: SQUONK2_UNIT_BILLING_DAY
  value: {{ . | quote }}
{{- end }}
{{- if .Values.email.user }}
- name: EMAIL_USER
  value: {{ .Values.email.user | quote }}
{{- if ne (toString .Values.email.host) "" }}
- name: EMAIL_HOST
  value: {{ .Values.email.host | quote }}
{{- end }}
{{- if ne (toString .Values.email.useTls) "" }}
- name: EMAIL_USE_TLS
  value: {{ .Values.email.useTls | quote }}
{{- end }}
{{- if ne (toString .Values.email.port) "" }}
- name: EMAIL_PORT
  value: {{ .Values.email.port | quote }}
{{- end }}
{{- with .Values.email.password }}
- name: EMAIL_PASSWORD
  value: {{ . | quote }}
{{- end }}
{{- end }}
- name: IBM_API_KEY
  value: {{ .Values.apiKeys.ibm | quote }}
- name: MANIFOLD_API_KEY
  value: {{ .Values.apiKeys.manifold | quote }}
- name: MCULE_API_KEY
  value: {{ .Values.apiKeys.mcule | quote }}
- name: SENDGRID_API_KEY
  value: {{ .Values.apiKeys.sendgrid | quote }}
- name: TA_AUTH_SERVICE
  value: {{ .Values.taAuth.service | quote }}
- name: TA_AUTH_QUERY_KEY
  value: {{ .Values.taAuth.queryKey | quote }}
{{- if .Values.xchem.host }}
- name: XCHEM_NAME
  valueFrom:
    secretKeyRef:
      name: xchem
      key: name
- name: XCHEM_USER
  valueFrom:
    secretKeyRef:
      name: xchem
      key: user
- name: XCHEM_PASSWORD
  valueFrom:
    secretKeyRef:
      name: xchem
      key: password
- name: XCHEM_HOST
  valueFrom:
    secretKeyRef:
      name: xchem
      key: host
- name: XCHEM_PORT
  valueFrom:
    secretKeyRef:
      name: xchem
      key: port
{{- end }}
- name: BUILD_XCDB
  value: {{ ternary "yes" "no" .Values.stack.buildXcdb | quote }}
- name: LOGGING_FRAMEWORK_ROOT_LEVEL
  value: {{ .Values.stack.loggingFrameworkRootLevel | quote }}
- name: TAS_REGEX
  value: {{ .Values.stack.tasRegex | quote }}
- name: TAS_REGEX_ERROR_MSG
  value: {{ .Values.stack.tasRegexErrorMsg | quote }}
{{- with .Values.stack.publicTas }}
- name: PUBLIC_TAS
  value: {{ . | quote }}
{{- end }}
{{- if .Values.stack.disableRestrictProposalsToMembership }}
- name: DISABLE_RESTRICT_PROPOSALS_TO_MEMBERSHIP
  value: "True"
{{- end }}
{{- with .Values.stack.restrictedTasUsers }}
- name: RESTRICTED_TAS_USERS
  value: {{ . | quote }}
{{- end }}
{{- with .Values.stack.infections }}
- name: INFECTIONS
  value: {{ . | quote }}
{{- end }}
{{- end }}
