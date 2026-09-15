## Start with the README

See [README.md](README.md) for the charts, installing them, sensitive values,
how the Ansible plays map to Helm commands and adopting an existing installation.
Each chart's `values.yaml` documents its values.

## Don't break these invariants

- **Secrets/passwords are written once.** The generated `database` and `django`
  secrets use `lookup` to re-use an existing secret's data instead of generating
  new values. Never make them unconditionally regenerate - it rotates live DB/django
  credentials. Generate each password in exactly one template; other objects
  read it from the secret (`secretKeyRef`), never from a second `randAlpha`
- **Object names and Pod selectors are fixed** (`stack`, `database`, `name: stack` ...).
  Containers address each other by name, selectors are immutable, and fixed names
  let Helm adopt Ansible-deployed installations. Don't derive them from the release name
- **Retained data.** The `database`/`media` PVCs and `database` Secret carry
  `helm.sh/resource-policy: keep`. Don't remove it from one without the others
- **Pre-existing volume guards** (`database.allowPreExistingVolume` /
  `media.allowPreExistingVolume`) exist to force a clean database and media volume
  between production→staging replications. Don't relax them
- **Kubernetes object templates** exist as one object per template file
- **Template file names** begin with the lowercase name of the object they represent
  (e.g. `configmap-`)
- Charts must pass `helm lint --strict` and `helm unittest`
- Merging to `main` releases any chart whose `Chart.yaml` `version` is new.
  Bump the version (semver, no `v` prefix) when changing a chart

## General Style

- Write the helm-unittest test before changing a template (TDD)
- In YAML, list items (`-`) align with their parent key (not indented under it),
  and YAML lists are preferred over inline `[]`
- Quote rendered string values (`{{ .Values.x | quote }}`), especially environment values
- No spaces in filenames
- Mark sensitive values `SENSITIVE` in `values.yaml`; never commit installation values
