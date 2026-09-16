# Fragalysis helm charts
Fragalysis consists of a “Stack” and a “Target Access Authenticator”.
The authenticator is a service that the stack uses to obtain a list of
"Target Access Strings" the logged-in user is authorised to access.

Install the authenticator first.

>   In the following we assume the pre-allocated **Namespace** for
    our objects is `argus` and a `KUBECONFIG` has been set that provides
    access to it.

## The authenticator
An example illustrating the values we need can be found in
`values-argus-taa.example.yaml`. The file can't be used directly,
you'll need to provide values to replace the "SET-ME" values in it.

With _real_ values set we can simply run Helm for the `xchem/ta-authenticator`
as described in the README.

Once installed you should find an `ssh-key` **Secret** and one running **Pod**
managed by the `ta-authenticator` **Deployment**.

## The stack
To deploy a viable stack you'll need to provide a significantly greater number
of variables - it's a complex application after all. Here's an example setting
the smallest number of variables. All you need to do is: -

1.  Setup a hostname that will be routed to the application ingress and then set
    `ingress -> hostname`. We will also need to understand how certificates are
    generated. In our cluster we use **nginx** and the standard (?) Kubernetes
    **CertManager**. The Ingress definitions rely on named Cluster Issuer records
    that will be different to the ones we use.
2.  With a hostname allocated we then need to provide `oidc` (Keycloak) client
    information (obtained from Diamond in our case) by defining values for
    `oidc -> rpClientSecret` and `oidc -> rpClientId`.

An example illustrating the values we need can be found in
`values-argus-stack.example.yaml`. The file can't be used directly,
you'll need to provide values to replace the "SET-ME" values in it.

>   The media volume in the example is artificially small to allow an
    installation test. Before deploying "for real" you must set this to `400Gi`
    or larger.

With _real_ values set, just run the helm command for the `xchem/fragalysis-stack`
shown in the README.

>   Because you might want to change the stack version at regular intervals
    we name the version on the command-line for the stack.

Installation from "cold" will take several minutes before all the Pods reach a
running state. Once they do you should find several running **Pods**: a `database`,
`stack`, and `worker` driven by **StatefulSets**, `redis`, `pgbouncer`, and `beat`
**Pods** driven by corresponding **Deployments**.

At the time of writing the stack consists of 6 Pods.
