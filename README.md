# step-kube-deploy

This step uses the kubectl executable to replace a [kubernetes deployment](http://kubernetes.io/docs/user-guide/deployments/).
Authentication options are passed along to the `kubectl` executable as is.

# Options:

- `deployment` The name of the deployment that needs to be updated.
- `tag` The tag of the image for the rolling update.
- `debug` (optional, default: `false`) List the kubectl before running it.
Warning, all environment variables are expanded, including the password.
- `raw-global-args` (optional) Arguments that are placed before `kubectl replace`.

## Kubectl flags

The following options are available as wercker properties. The values are passed
directly to the `kubectl` command. See the `kubectl` for the documentation.

- `insecure-skip-tls-verify`
- `password`
- `server`
- `token`
- `username`

If a flag is not available, use the `raw-global-args`.

# Example

```
deploy:
    steps:
      - morriz/step-kube-deploy:
          server: $KUBERNETES_MASTER
          username: $KUBERNETES_USERNAME
          password: $KUBERNETES_PASSWORD
          insecure-skip-tls-verify: true
          deployment: create -f cities-controller.json
          tag: $WERCKER_GIT_COMMIT
```

# License

The MIT License (MIT)