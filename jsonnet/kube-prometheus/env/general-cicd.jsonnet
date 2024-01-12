{
    kube_prometheus: {
        # canonical name for the cluster we're deploying on
        cluster_name: 'general-cicd',
        namespace: 'pf9-kube-monitoring',

        # prometheus remote_write config
        remote_write: {
            url: 'https://pf9-kdu.cortex-dev-s3.infrastructure.rspc.platform9.horse/api/prom/push',
            onepassword_path: 'vaults/pf9-devops/items/pf9-kdu-cortex-dev-s3-auth'
        },
        replicas: {
            kubeStateMetrics: 2,
            prometheusK8s: 6,
        },
        resources:{
            kubeStateMetrics:{
               requests: { cpu: '20m', memory: '1Gi' },
               limits: { cpu: '200m', memory: '2Gi' },
            },
            prometheusK8s:{
               requests: { cpu: '1', memory: '4Gi' },
               limits: { cpu: '2', memory: '16Gi' },
            },
        },       
    },
}

