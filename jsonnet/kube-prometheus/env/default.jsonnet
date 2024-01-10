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
            kubeStateMetrics: 1,
            prometheusK8s: 2,
        },
        resources:{
            kubeStateMetrics:{
               requests: { cpu: '10m', memory: '500Mi' },
               limits: { cpu: '100m', memory: '1Gi' },
            },
            prometheusK8s:{
               requests: { cpu: '1', memory: '1Gi' },
               limits: { cpu: '2', memory: '4Gi' },
            },
        },        
    },
}

