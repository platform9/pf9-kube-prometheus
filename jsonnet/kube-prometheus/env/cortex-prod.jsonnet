{
    kube_prometheus: {
        # canonical name for the cluster we're deploying on
        cluster_name: 'pf9-cortex-prod',
        namespace: 'monitoring',

        # prometheus remote_write config
        remote_write: {
            url: 'https://internal.pf9cortex.platform9.net/api/prom/push',
            onepassword_path: 'vaults/pf9-devops/items/internal-remote-read-write'
        },
        replicas: {
            kubeStateMetrics: 1
        },
        resources:{
            kubeStateMetrics:{
               requests: { cpu: '20m', memory: '1Gi' },
               limits: { cpu: '200m', memory: '2Gi' },
            }
        },       
    },
}

