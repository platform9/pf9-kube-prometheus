{
    kube_prometheus: {
        # canonical name for the cluster we're deploying on
        cluster_name: 'default',
        namespace: 'monitoring',

        # prometheus remote_write config
        remote_write: {
            url: 'https://internal.cortex-dev-s3.infrastructure.rspc.platform9.horse/api/prom/push',
            onepassword_path: 'vaults/pf9-devops/items/cortex-dev-internal'
        },
        replicas: {
            kubeStateMetrics: 1
        },        
    },
}

