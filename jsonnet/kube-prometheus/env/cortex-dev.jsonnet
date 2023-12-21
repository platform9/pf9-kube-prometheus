{
    kube_prometheus: {
        # canonical name for the cluster we're deploying on
        cluster_name: 'cortex-dev-s3',
        namespace: 'monitoring',

        # prometheus remote_write config
        remote_write: {
            url: 'https://cortex-dev-s3.infrastructure.rspc.platform9.horse/api/prom/push',
            onepassword_path: 'vaults/pf9-devops/items/cortex-dev-primary-basic-auth'
        },
    },
}

