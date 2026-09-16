# Fragalysis helm charts
Fragalysis consists of a “Stack” and a “Target Access Authenticator”.
The authenticator is a service that the stack uses to obtain a list of
"Target Access Strings" the logged-in user is authorised to access.

Install the authenticator first.

>   In the following we assume the pre-allocated **Namespace** for
    our objects is `argus` and a `KUBECONFIG` has been set that provides
    access to it.

## The authenticator
Minimal values we need, in the `values-argus-taa.yaml` file, are: -

```yaml
---
# We need to provide the version of the authenticator.
# There is a default but it's better to check the source repository
# to select the version that you need.
image:
  tag: "1.5.1"
# The ISPyB authenticator at Diamond will need ISPyB and SSH credentials
# that allow it to access your chosen underlying ISPyB server.
# Get password and privateKey values from your system administrator.
ispyb:
  host: ispybdbproxy.diamond.ac.uk
  port: 4306
  user: ispyb-user
  password: password1234
ssh:
  host: ssh.diamond.ac.uk
  user: fragalysis-user
  privateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn
    ...
    -----END OPENSSH PRIVATE KEY-----
```

With values set we can simply run Helm for the `xchem/ta-authenticator`
as described in the README.

Once installed you should find an `ssh-key` **Secret** and a running **Pod**
managed by the `ta-authenticator` **Deployment**.

## The stack
