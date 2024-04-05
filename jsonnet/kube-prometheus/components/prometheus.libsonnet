local environment_vars = import '../environment.jsonnet';
local defaults = {
  local defaults = self,
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources:: {
    requests: { cpu: environment_vars.kube_prometheus.resources.prometheusK8s.requests.cpu, memory: environment_vars.kube_prometheus.resources.prometheusK8s.requests.memory },
    limits: { cpu: environment_vars.kube_prometheus.resources.prometheusK8s.limits.cpu, memory: environment_vars.kube_prometheus.resources.prometheusK8s.limits.memory },
  },

  name: error 'must provide name',
  alertmanagerName: error 'must provide alertmanagerName',
  namespaces: ['default', 'kube-system', defaults.namespace],
  replicas: 2,
  externalLabels: { cluster: environment_vars.kube_prometheus.cluster_name},
  enableFeatures: [],
  commonLabels:: {
    'app.kubernetes.io/name': 'prometheus',
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'prometheus',
    'app.kubernetes.io/part-of': 'kube-prometheus',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  } + { prometheus: defaults.name },
  ruleSelector: {},
  mixin: {
    ruleLabels: {},
    _config: {
      prometheusSelector: 'job="prometheus-' + defaults.name + '",namespace="' + defaults.namespace + '"',
      prometheusName: '{{$labels.namespace}}/{{$labels.pod}}',
      thanosSelector: 'job="thanos-sidecar"',
      runbookURLPattern: 'https://runbooks.prometheus-operator.dev/runbooks/prometheus/%s',
    },
  },
  thanos: null,
};


function(params) {
  local p = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject(p._config.resources),
  assert std.isObject(p._config.mixin._config),

  mixin::
    (import 'github.com/prometheus/prometheus/documentation/prometheus-mixin/mixin.libsonnet') +
    (import 'github.com/kubernetes-monitoring/kubernetes-mixin/lib/add-runbook-links.libsonnet') + {
      _config+:: p._config.mixin._config,
    },

  mixinThanos::
    (import 'github.com/thanos-io/thanos/mixin/alerts/sidecar.libsonnet') +
    (import 'github.com/kubernetes-monitoring/kubernetes-mixin/lib/add-runbook-links.libsonnet') + {
      _config+:: p._config.mixin._config,
      targetGroups: {},
      sidecar: {
        selector: p._config.mixin._config.thanosSelector,
        dimensions: std.join(', ', ['job', 'instance']),
      },
    },

  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: {
      labels: p._config.commonLabels + p._config.mixin.ruleLabels,
      name: 'prometheus-' + p._config.name + '-prometheus-rules',
      namespace: p._config.namespace,
    },
    spec: {
      local r = if std.objectHasAll(p.mixin, 'prometheusRules') then p.mixin.prometheusRules.groups else [],
      local a = if std.objectHasAll(p.mixin, 'prometheusAlerts') then p.mixin.prometheusAlerts.groups else [],
      groups: a + r,
    },
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: 'prometheus-' + p._config.name,
      namespace: p._config.namespace,
      labels: p._config.commonLabels,
    },
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: 'prometheus-' + p._config.name,
      namespace: p._config.namespace,
      labels: { prometheus: p._config.name } + p._config.commonLabels,
    },
    spec: {
      ports: [
               { name: 'web', targetPort: 'web', port: 9090 },
             ] +
             (
               if p._config.thanos != null then
                 [{ name: 'grpc', port: 10901, targetPort: 10901 }]
               else []
             ),
      selector: { app: 'prometheus' } + p._config.selectorLabels,
      sessionAffinity: 'ClientIP',
    },
  },

  roleBindingSpecificNamespaces:
    local newSpecificRoleBinding(namespace) = {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: {
        name: 'prometheus-' + p._config.name,
        namespace: namespace,
        labels: p._config.commonLabels,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: 'prometheus-' + p._config.name,
      },
      subjects: [{
        kind: 'ServiceAccount',
        name: 'prometheus-' + p._config.name,
        namespace: p._config.namespace,
      }],
    };
    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBindingList',
      items: [newSpecificRoleBinding(x) for x in p._config.namespaces],
    },

  clusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: 'prometheus-' + p._config.name,
      labels: p._config.commonLabels,
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['nodes/metrics'],
        verbs: ['get'],
      },
      {
        apiGroups: [''],
        resources: ['services', 'endpoints', 'pods'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        nonResourceURLs: ['/metrics'],
        verbs: ['get'],
      },
    ],
  },

  roleConfig: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: {
      name: 'prometheus-' + p._config.name + '-config',
      namespace: p._config.namespace,
      labels: p._config.commonLabels,
    },
    rules: [{
      apiGroups: [''],
      resources: ['configmaps'],
      verbs: ['get'],
    }],
  },

  roleBindingConfig: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: {
      name: 'prometheus-' + p._config.name + '-config',
      namespace: p._config.namespace,
      labels: p._config.commonLabels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: 'prometheus-' + p._config.name + '-config',
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: 'prometheus-' + p._config.name,
      namespace: p._config.namespace,
    }],
  },

  clusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'prometheus-' + p._config.name,
      labels: p._config.commonLabels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'prometheus-' + p._config.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: 'prometheus-' + p._config.name,
      namespace: p._config.namespace,
    }],
  },

  roleSpecificNamespaces:
    local newSpecificRole(namespace) = {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        name: 'prometheus-' + p._config.name,
        namespace: namespace,
        labels: p._config.commonLabels,
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['services', 'endpoints', 'pods'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['extensions'],
          resources: ['ingresses'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['networking.k8s.io'],
          resources: ['ingresses'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    };
    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleList',
      items: [newSpecificRole(x) for x in p._config.namespaces],
    },

  [if (defaults + params).replicas > 1 then 'podDisruptionBudget']: {
    apiVersion: 'policy/v1beta1',
    kind: 'PodDisruptionBudget',
    metadata: {
      name: 'prometheus-' + p._config.name,
      namespace: p._config.namespace,
      labels: p._config.commonLabels,
    },
    spec: {
      minAvailable: 1,
      selector: {
        matchLabels: {
          prometheus: p._config.name,
        } + p._config.selectorLabels,
      },
    },
  },

  prometheus: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'Prometheus',
    metadata: {
      name: p._config.name,
      namespace: p._config.namespace,
      labels: { prometheus: p._config.name } + p._config.commonLabels,
    },
    spec: {
      replicas: environment_vars.kube_prometheus.replicas.prometheusK8s,
      version: p._config.version,
      image: p._config.image,
      podMetadata: {
        labels: p._config.commonLabels,
      },
      externalLabels: p._config.externalLabels,
      replicaExternalLabelName: "",
      remoteWrite: [
          {
              basicAuth: {
                  password: {
                      key: "password",
                      name: "remotewrite-basicauth-prometheus",
                  },
                  username: {
                      key: "username",
                      name: "remotewrite-basicauth-prometheus",
                  }
              },  
              url: environment_vars.kube_prometheus.remote_write.url,
              remoteTimeout: '2m',
              # trade larger request sizes for request volume/rate
              # this helps ease burden on the nginx proxy for authentication
              queueConfig: {
                  maxShards: 100,
                  maxSamplesPerSend: 1000,
                  capacity: 1000,  
              },
              tlsConfig: {
                insecureSkipVerify: true,
              },         
              # filter out metrics globally that are expensive and/or we don't need
              writeRelabelConfigs: [

                    # standard issue go-generated series that no one looks at
                    # (and are often redundant in cases such as consul)
                    {
                        action: "drop",
                        regex: "go_.*",
                        sourceLabels: ["__name__"]
                    },

                    # Drop the externalLabel with key 'prometheus_replica'
                    #{
                    #    action: "labeldrop",
                    #    regex: "prometheus_replica"
                    #},

                    # the value of the "service" label (tacked on by the prometheus
                    # operator) matches the "job" label, making it redundant
                    {
                        action: "labeldrop",
                        regex: "^service$"
                    },

                    # kubernetes_sd_configs labels deemed redundant
                    {
                        action: "labeldrop",
                        regex: "^pod_template_generation$"
                    },
                    {
                        action: "labeldrop",
                        regex: "^controller_revision_hash$"
                    },

                    # Additional metric drop from the node exporter which were dropped before
                    {
                        action: "drop",
                        regex: "(node_network_(address_assign_type|device_id|protocol_type|carrier_changes_total))",
                        sourceLabels: ["__name__"]
                    },
                    {
                        action: "labeldrop",
                        regex: "pod_template_generation"
                    },
                    {
                        action: "labeldrop",
                        regex: "controller_revision_hash"
                    },
                    {
                        action: "labeldrop",
                        regex: "topology_kubernetes_io_region"
                    },
                    {
                        action: "labeldrop",
                        regex: "(beta_)?kubernetes_io_arch"
                    },
                    {
                        action: "labeldrop",
                        regex: "(beta_)?kubernetes_io_os"
                    },

                    # filter out any fs info from mounts we don't care about
                    # (e.g. mounted by docker, systemd)
                    {
                        action: "drop",
                        regex: "node_filesystem_[^;]+;(/var/lib/.+|/run.*)",
                        sourceLabels: ["__name__","mountpoint"]
                    },                    
                ]
          }
      ],            
      enableFeatures: p._config.enableFeatures,
      serviceAccountName: 'prometheus-' + p._config.name,
      podMonitorSelector: {},
      podMonitorNamespaceSelector: {},
      probeSelector: {},
      probeNamespaceSelector: {},
      ruleNamespaceSelector: {},
      ruleSelector: p._config.ruleSelector,
      serviceMonitorSelector: {},
      serviceMonitorNamespaceSelector: {},
      nodeSelector: { 'kubernetes.io/os': 'linux' },
      resources: p._config.resources,
      alerting: {
        alertmanagers: [{
          namespace: p._config.namespace,
          name: 'alertmanager-' + p._config.alertmanagerName,
          port: 'web',
          apiVersion: 'v2',
        }],
      },
      securityContext: {
        runAsUser: 1000,
        runAsNonRoot: true,
        fsGroup: 2000,
      },
      [if std.objectHas(params, 'thanos') then 'thanos']: p._config.thanos,
    },
  },

  serviceMonitor: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: {
      name: 'prometheus-' + p._config.name,
      namespace: p._config.namespace,
      labels: p._config.commonLabels,
    },
    spec: {
      selector: {
        matchLabels: p._config.selectorLabels,
      },
      endpoints: [{
        port: 'web',
        interval: '2m',
        metricRelabelings: [
          {
            // Dropping unwanted metrics
            sourceLabels: ['__name__'],
            regex: 'prometheus_(engine|http|notifications|remote_storage_string|rule_group|sd|target|template|treecache|tsdb_block|tsdb_data|tsdb_exemplar|tsdb_isolation)_.*',
            action: 'drop',
          },
          {
            // Dropping unwanted metrics
            sourceLabels: ['__name__'],
            regex: 'prometheus_(remote_storage_e|remote_storage_h|remote_storage_m|remote_storage_shard|tsdb_c|tsdb_l|tsdb_m|tsdb_o|tsdb_r|tsdb_t|tsdb_v|tsdb_w|w).*',
            action: 'drop',
          },
          {
            // Dropping unwanted metrics
            sourceLabels: ['__name__'],
            regex: 'go_.*|net_conntrack_.*|promhttp_metric_.*|reloader_.*',
            action: 'drop',
          },
        ],
      }],
    },
  },

  // Include thanos sidecar PrometheusRule only if thanos config was passed by user
  [if std.objectHas(params, 'thanos') && params.thanos != null then 'prometheusRuleThanosSidecar']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: {
      labels: p._config.commonLabels + p._config.mixin.ruleLabels,
      name: 'prometheus-' + p._config.name + '-thanos-sidecar-rules',
      namespace: p._config.namespace,
    },
    spec: {
      local r = if std.objectHasAll(p.mixinThanos, 'prometheusRules') then p.mixinThanos.prometheusRules.groups else [],
      local a = if std.objectHasAll(p.mixinThanos, 'prometheusAlerts') then p.mixinThanos.prometheusAlerts.groups else [],
      groups: a + r,
    },
  },

  // Include thanos sidecar Service only if thanos config was passed by user
  [if std.objectHas(params, 'thanos') && params.thanos != null then 'serviceThanosSidecar']: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata+: {
      name: 'prometheus-' + p._config.name + '-thanos-sidecar',
      namespace: p._config.namespace,
      labels+: p._config.commonLabels {
        prometheus: p._config.name,
        'app.kubernetes.io/component': 'thanos-sidecar',
      },
    },
    spec+: {
      ports: [
        { name: 'grpc', port: 10901, targetPort: 10901 },
        { name: 'http', port: 10902, targetPort: 10902 },
      ],
      selector: p._config.selectorLabels {
        prometheus: p._config.name,
        'app.kubernetes.io/component': 'prometheus',
      },
      clusterIP: 'None',
    },
  },

  // Include thanos sidecar ServiceMonitor only if thanos config was passed by user
  [if std.objectHas(params, 'thanos') && params.thanos != null then 'serviceMonitorThanosSidecar']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: 'thanos-sidecar',
      namespace: p._config.namespace,
      labels: p._config.commonLabels {
        prometheus: p._config.name,
        'app.kubernetes.io/component': 'thanos-sidecar',
      },
    },
    spec+: {
      jobLabel: 'app.kubernetes.io/component',
      selector: {
        matchLabels: {
          prometheus: p._config.name,
          'app.kubernetes.io/component': 'thanos-sidecar',
        },
      },
      endpoints: [{
        port: 'http',
        interval: '30s',
      }],
    },
  },
}
