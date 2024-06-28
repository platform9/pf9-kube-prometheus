# Secrets for monitoring
local environment_vars = import '../environment.jsonnet';
{
    onepassword_remote_write:{
        apiVersion: 'onepassword.com/v1',
        kind: 'OnePasswordItem',
        metadata: {
            name: 'remotewrite-basicauth-prometheus',
            namespace: environment_vars.kube_prometheus.namespace,
        },
        spec: {
            itemPath: environment_vars.kube_prometheus.remote_write.onepassword_path
        }
    }
}