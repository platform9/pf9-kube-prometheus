{
    kube_prometheus: {
        # canonical name for the cluster we're deploying on
        cluster_name: 'general-cicd',
        namespace: 'monitoring',

        # prometheus remote_write config
        remote_write: {
            url: 'https://pf9-kdu.cortex-dev-s3.infrastructure.rspc.platform9.horse/api/prom/push',
            onepassword_path: 'vaults/pf9-devops/items/pf9-kdu-cortex-dev-s3-auth'
        },
    },
}

