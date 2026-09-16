# Fragalysis Helm

Helm charts that deploy the components of the **Fragalysis** suite into
Kubernetes. They are a port of the [fragalysis-ansible] roles: -

| Chart                      | Deploys                                                                   |
|----------------------------|---------------------------------------------------------------------------|
| `charts/fragalysis-stack`  | The Fragalysis Stack: the Django web app, Celery worker and beat, PostgreSQL, pgBouncer, Redis and optional backups |
| `charts/ta-authenticator`  | The (ISPyB) Target Access Authenticator and its memcached sidecar         |

## Prerequisites

- [Helm] (the charts are developed with v4)
- Access to a Kubernetes cluster and an existing **Namespace**
- [cert-manager] if you want Ingress certificates, and the Prometheus
  operator CRDs if you enable stack metrics

## Installing

The charts are published to a Helm repository: -

```bash
helm repo add xchem https://xchem.github.io/fragalysis-helm
helm repo update
```

Both charts deploy into the release namespace. The stack and the
authenticator are designed to share a namespace, where the stack reaches
the authenticator at `http://auth`: -

```bash
helm upgrade --install ta-authenticator xchem/ta-authenticator \
  --version 1.0.0 \
  --namespace argus -f values-argus-taa.yaml --wait

helm upgrade --install fragalysis-stack xchem/fragalysis-stack \
  --version 1.0.0 \
  --namespace argus -f values-argus-stack.yaml \
  --set stack.image.tag=2026.09.1 \
  --wait --timeout 10m
```

Each chart is versioned independently. `--version` selects the chart
version. Without it Helm uses the newest version found by the last
`helm repo update`, so pin it for production installations. To list the
published versions: -

```bash
helm search repo xchem --versions
```

The chart version is not the application version. The stack's image is
set with `stack.image.tag`, and the authenticator's image defaults to its
chart's `appVersion` (unless `image.tag` is set).

From a clone of this repository use `charts/<chart>` in place of
`xchem/<chart>` (and omit `--version`).

In the stack's values, point it at the authenticator: -

```yaml
taAuth:
  service: http://auth
  queryKey: <the authenticator's queryKey>
```

If the authenticator has no `queryKey` its query endpoint is not secured
and the stack does not need a `taAuth.queryKey`.

The stack chart requires `stack.image.tag` and (unless
`stack.waitForGraph` is `false`) `graph.hostname`.

Kubernetes object names are fixed (`stack`, `database`, `redis`, `auth`
...) because the containers address each other by these names. Install at
most one release of each chart in a namespace.

## Values

Each chart's `values.yaml` is its documentation. Read it before adding a
value. As a guide, the Ansible variables map to values like this: -

| Ansible                                   | Helm                                        |
|-------------------------------------------|---------------------------------------------|
| `stack_image_tag`                         | `stack.image.tag`                           |
| `stack_skip_deploy`                       | `stack.deploy` (inverted)                   |
| `stack_hostname`, `stack_ingress_class`, `stack_cert_issuer` | `ingress.hostname`, `ingress.className`, `ingress.certIssuer` |
| `stack_cpu_limit`, `stack_mem_request` ... | `stack.resources`                          |
| `stack_media_vol_size_g: 400`             | `media.volume.size: 400Gi`                  |
| `database_bu_state: present`              | `backups.database.enabled: true`            |
| `pgbouncer_tag: ""`                       | `pgbouncer.enabled: false`                  |
| `redis_vol_size_g: 0`                     | `redis.volume.enabled: false`               |
| `taa_auth_hostname`                       | `ingress.authHostname`                      |
| `wait_timeout`                            | `helm --wait --timeout`                     |

### Sensitive values

Values marked `SENSITIVE` in `values.yaml` (passwords, keys, S3
credentials) replace the Ansible vault files. The chart repository holds no
installation material. Keep each installation's sensitive values out of
plain-text version control, for example: -

- in a values file encrypted with [SOPS] and applied with the
  [helm-secrets] plugin, or
- in your CI secrets, written to a values file (or passed with `--set`)
  at deploy time.

## From Ansible plays to Helm commands

| Ansible play                                        | Helm                                                                                     |
|-----------------------------------------------------|------------------------------------------------------------------------------------------|
| `site-fragalysis-stack.yaml`                        | `helm upgrade --install fragalysis-stack ...`                                            |
| `site-fragalysis-stack_update.yaml`                 | `helm upgrade fragalysis-stack ... --reuse-values --set stack.image.tag=<tag>`           |
| `site-fragalysis-stack_shutdown.yaml`               | `helm upgrade fragalysis-stack ... --reuse-values --set stack.deploy=false`              |
| `site-fragalysis-stack_wipe.yaml`                   | `helm uninstall fragalysis-stack`, then delete the retained volumes (see below)          |
| `site-fragalysis-stack.yaml -e stack_state=absent`  | `helm uninstall fragalysis-stack`, then delete the retained volumes and database secret  |
| `site-ta-authenticator.yaml`                        | `helm upgrade --install ta-authenticator ...` (`helm uninstall` to remove it)            |

A **shutdown** (`stack.deploy=false`) removes the stack, worker, beat,
redis and the django secret. The database, the stack Service and Ingress
remain, as does the media volume (delete it with
`kubectl delete pvc media` if you want to). Set `stack.deploy=true` to
deploy the stack again.

Helm retains these objects when the stack is shut down or uninstalled.
They carry the `helm.sh/resource-policy: keep` annotation: -

- The `database` and `media` PersistentVolumeClaims
- The `database` Secret (it holds the passwords of the retained database)

Delete them with `kubectl` when you really want them gone: -

```bash
kubectl delete pvc database media --namespace argus
kubectl delete secret database --namespace argus
```

## Behaviour worth knowing

- **Secrets are written once.** The `database` and `django` secrets hold
  generated passwords. The chart uses Helm's `lookup` to find an existing
  secret and, if one exists, re-uses its values rather than generating new
  ones - rotating them would break the live database and django
  credentials. `lookup` needs a cluster, so `helm template` (and a
  client-side `--dry-run`) always shows newly generated values.
- **Pre-existing volume guards.** Set `database.allowPreExistingVolume` (with
  `stack.deploy=false`) or `media.allowPreExistingVolume` to `false` and the
  chart refuses to render if the corresponding volume exists. These enforce
  a clean database and media volume between production to staging
  replications.
- **Mutable image tags roll out on every upgrade.** If the stack image pull
  policy is `Always` (the default for `latest` and `stable` tags) the stack,
  worker and beat Pods are annotated with the deployment time.
- **Readiness.** Use `helm --wait --timeout` in place of the playbooks'
  readiness polling. The stack's init containers wait for the database,
  graph and redis to be resolvable.

### Differences from the Ansible roles

- The database user password is no longer copied into the `postgres-init`
  ConfigMap or a separate `pgbouncer` Secret. The init script and pgBouncer
  read it from the `database` Secret.
- The authenticator's SSH private key is held in a Secret rather than a
  ConfigMap.
- The authenticator's `keys` Secret is written from values on every upgrade
  (it holds supplied, not generated, keys).
- An external database (`database.host`) no longer deploys pgBouncer or
  waits for an in-cluster `database` service. You must provide a `database`
  secret with a `user_password` key.

## Adopting an existing Ansible installation

The charts use the Ansible object names and Pod selectors, so Helm can
take over an installation deployed by the playbooks. Helm refuses to
manage objects it did not create unless they carry its ownership metadata.
Before the first `helm upgrade --install`, label and annotate each object
the release will manage, e.g. for the stack in `argus`: -

```bash
NS=argus
RELEASE=fragalysis-stack
for obj in serviceaccount/stack secret/database secret/django \
    configmap/postgres-conf configmap/postgres-init configmap/redis-conf \
    pvc/database pvc/media service/database service/pgbouncer service/redis \
    service/stack ingress/stack deployment/pgbouncer deployment/redis \
    deployment/beat statefulset/database statefulset/stack statefulset/worker; do
  kubectl --namespace $NS label "$obj" app.kubernetes.io/managed-by=Helm --overwrite
  kubectl --namespace $NS annotate "$obj" --overwrite \
    meta.helm.sh/release-name=$RELEASE meta.helm.sh/release-namespace=$NS
done
```

Add any optional objects you use (`secret/xchem`, `secret/backup-rclone`,
`secret/backup-rsync`, `pvc/redis`, `pvc/database-backup`, the backup
`cronjob`s and `servicemonitor/fragalysis-stack`). Because the existing
`database` and `django` secrets are adopted, their credentials are
preserved. The Ansible `pgbouncer` Secret (and the authenticator's
`ssh-key` ConfigMap) are no longer used and can be deleted.

## Development

Chart behaviour is covered by [helm-unittest] suites in each chart's
`tests` directory. Write (or change) a test before changing a template: -

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git \
  --version v1.1.2 --verify=false

helm unittest charts/*
helm lint --strict charts/fragalysis-stack \
  --set stack.image.tag=lint --set graph.hostname=graph
helm lint --strict charts/ta-authenticator
```

To see what a chart renders: -

```bash
helm template fragalysis-stack charts/fragalysis-stack --namespace argus \
  --set stack.image.tag=latest --set graph.hostname=graph.graph.svc
```

## Releasing

Charts are released when changes reach `main`. The `release` workflow
uses [chart-releaser] to publish every chart whose `Chart.yaml` `version`
has not been released before. It creates a GitHub release (and tag) named
`<chart>-<version>` and updates the repository index on the `gh-pages`
branch. To release a chart, bump its `version` (semver, no `v` prefix) in
the pull request that changes it.
Update the chart's `--version` in the [Installing](#installing) commands
at the same time.

## License

Licensed under the [Apache License, Version 2.0][apache-2.0]; the full
text is in the [LICENSE][license] file.

---

[apache-2.0]: https://www.apache.org/licenses/LICENSE-2.0
[cert-manager]: https://cert-manager.io
[chart-releaser]: https://github.com/helm/chart-releaser
[fragalysis-ansible]: https://github.com/xchem/fragalysis-ansible
[helm]: https://helm.sh
[helm-secrets]: https://github.com/jkroepke/helm-secrets
[helm-unittest]: https://github.com/helm-unittest/helm-unittest
[license]: LICENSE
[sops]: https://github.com/getsops/sops
