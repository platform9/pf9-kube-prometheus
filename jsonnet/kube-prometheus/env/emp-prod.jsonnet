{
    kube_prometheus: {
        # canonical name for the cluster we're deploying on
        cluster_name: 'emp-prod',
        namespace: 'monitoring',

        # prometheus remote_write config
        remote_write: {
            url: 'https://pmkft.cortex.platform9.net/api/prom/push',
            onepassword_path: 'vaults/emp-prod/items/pmkft-remote-read-write'
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

