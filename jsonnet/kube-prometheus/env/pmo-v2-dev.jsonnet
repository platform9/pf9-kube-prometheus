{
    kube_prometheus: {
        # canonical name for the cluster we're deploying on
        cluster_name: 'pmo-v2-dev',
        namespace: 'monitoring',

        # prometheus remote_write config
        remote_write: {
            url: 'https://pmo-v2-dev.pf9cortex.platform9.net/api/prom/push',
            onepassword_path: 'vaults/pmo-v2-dev/items/cortex-credentials-dev'
        },
        replicas: {
            kubeStateMetrics: 2,
            prometheusK8s: 1,
        },
        resources:{
            kubeStateMetrics:{
               requests: { cpu: '20m', memory: '1Gi' },
               limits: { cpu: '200m', memory: '2Gi' },
            },
            prometheusK8s:{
               requests: { cpu: '1', memory: '1Gi' },
               limits: { cpu: '2', memory: '4Gi' },
            },
        },
    },
}
