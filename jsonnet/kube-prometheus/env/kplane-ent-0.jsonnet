{
    kube_prometheus: {
        # canonical name for the cluster we're deploying on
        cluster_name: 'enterprise-0',
        namespace: 'monitoring',

        # prometheus remote_write config
        remote_write: {
            url: 'https://pmkft.pf9cortex.platform9.net/api/prom/push',
            onepassword_path: 'vaults/pf9-devops/items/cortex-prod-pmkft-basic-auth'
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
