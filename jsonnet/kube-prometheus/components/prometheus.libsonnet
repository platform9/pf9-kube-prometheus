local environment_vars = import '../environment.jsonnet';
local defaults = {
  local defaults = self,
  // Convention: Top-level fields related to CRDs are public, other fields are hidden
  // If there is no CRD for the component, everything is hidden in defaults.
  name:: error 'must provide name',
  namespace:: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources:: {
    requests: { cpu: environment_vars.kube_prometheus.resources.prometheusK8s.requests.cpu, memory: environment_vars.kube_prometheus.resources.prometheusK8s.requests.memory },
    limits: { cpu: environment_vars.kube_prometheus.resources.prometheusK8s.limits.cpu, memory: environment_vars.kube_prometheus.resources.prometheusK8s.limits.memory },
  },
  scrapeInterval:: '30s',
  scrapeTimeout:: '60s',
  //TODO(paulfantom): remove alertmanagerName after release-0.10 and convert to plain 'alerting' object.
  alertmanagerName:: '',
  alerting: {},
  namespaces:: ['default', 'kube-system', defaults.namespace],
  replicas: 2,
  externalLabels: { cluster: environment_vars.kube_prometheus.cluster_name},
  enableFeatures: [],
  ruleSelector: {},
  commonLabels:: {
    'app.kubernetes.io/name': 'prometheus',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'prometheus',
    'app.kubernetes.io/part-of': 'kube-prometheus',
  },
  selectorLabels:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
  mixin:: {
    ruleLabels: {},
    _config: {
      prometheusSelector: 'job="prometheus-' + defaults.name + '",namespace="' + defaults.namespace + '"',
      prometheusName: '{{$labels.namespace}}/{{$labels.pod}}',
      // TODO: remove `thanosSelector` after 0.10.0 release.
      thanosSelector: 'job="thanos-sidecar"',
      thanos: {
        targetGroups: {
          namespace: defaults.namespace,
        },
        sidecar: {
          selector: defaults.mixin._config.thanosSelector,
          thanosPrometheusCommonDimensions: 'namespace, pod',
        },
      },
      runbookURLPattern: 'https://runbooks.prometheus-operator.dev/runbooks/prometheus/%s',
    },
  },
  thanos: null,
  reloaderPort:: 8080,
};


function(params) {
  local p = self,
  _config:: defaults + params,
  // Safety check
  assert std.isObject(p._config.resources),
  assert std.isObject(p._config.mixin._config),
  _metadata:: {
    name: 'prometheus-' + p._config.name,
    namespace: p._config.namespace,
    labels: p._config.commonLabels,
  },

  mixin::
    (import 'github.com/prometheus/prometheus/documentation/prometheus-mixin/mixin.libsonnet') +
    (import 'github.com/kubernetes-monitoring/kubernetes-mixin/lib/add-runbook-links.libsonnet') + {
      _config+:: p._config.mixin._config,
    },

  mixinThanos::
    (import 'github.com/thanos-io/thanos/mixin/alerts/sidecar.libsonnet') +
    (import 'github.com/kubernetes-monitoring/kubernetes-mixin/lib/add-runbook-links.libsonnet') + {
      _config+:: p._config.mixin._config,
      targetGroups+: p._config.mixin._config.thanos.targetGroups,
      // TODO: remove `_config.thanosSelector` after 0.10.0 release.
      sidecar+: { selector: p._config.mixin._config.thanosSelector } + p._config.mixin._config.thanos.sidecar,
    },

  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: p._metadata {
      labels+: p._config.mixin.ruleLabels,
      name: p._metadata.name + '-prometheus-rules',
    },
    spec: {
      local r = if std.objectHasAll(p.mixin, 'prometheusRules') then p.mixin.prometheusRules.groups else [],
      local a = if std.objectHasAll(p.mixin, 'prometheusAlerts') then p.mixin.prometheusAlerts.groups else [],
      groups: a + r,
    },
  },

  networkPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: p.service.metadata,
    spec: {
      podSelector: {
        matchLabels: p._config.selectorLabels,
      },
      policyTypes: ['Egress', 'Ingress'],
      egress: [{}],
      ingress: [{
        from: [{
          podSelector: {
            matchLabels: {
              'app.kubernetes.io/name': 'prometheus',
            },
          },
        }],
        ports: std.map(function(o) {
          port: o.port,
          protocol: 'TCP',
        }, p.service.spec.ports),
      }, {
        from: [{
          podSelector: {
            matchLabels: {
              'app.kubernetes.io/name': 'prometheus-adapter',
            },
          },
        }],
        ports: [{
          port: 9090,
          protocol: 'TCP',
        }],
      }, {
        from: [{
          podSelector: {
            matchLabels: {
              'app.kubernetes.io/name': 'grafana',
            },
          },
        }],
        ports: [{
          port: 9090,
          protocol: 'TCP',
        }],
      }] + (if p._config.thanos != null then
              [{
                from: [{
                  podSelector: {
                    matchLabels: {
                      'app.kubernetes.io/name': 'thanos-query',
                    },
                  },
                }],
                ports: [{
                  port: 10901,
                  protocol: 'TCP',
                }],
              }] else []),
    },
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: p._metadata,
    automountServiceAccountToken: true,
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: p._metadata,
    spec: {
      ports: [
               { name: 'web', targetPort: 'web', port: 9090 },
               { name: 'reloader-web', port: p._config.reloaderPort, targetPort: 'reloader-web' },
             ] +
             (
               if p._config.thanos != null then
                 [{ name: 'grpc', port: 10901, targetPort: 10901 }]
               else []
             ),
      selector: p._config.selectorLabels,
      sessionAffinity: 'ClientIP',
    },
  },

  roleBindingSpecificNamespaces:
    local newSpecificRoleBinding(namespace) = {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: p._metadata {
        namespace: namespace,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: p._metadata.name,
      },
      subjects: [{
        kind: 'ServiceAccount',
        name: p.serviceAccount.metadata.name,
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
    metadata: p._metadata {
      namespace:: null,
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['nodes/metrics'],
        verbs: ['get'],
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
    metadata: p._metadata {
      name: p._metadata.name + '-config',
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
    metadata: p._metadata {
      name: p._metadata.name + '-config',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: p.roleConfig.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: p.serviceAccount.metadata.name,
      namespace: p._config.namespace,
    }],
  },

  clusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: p._metadata {
      namespace:: null,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: p.clusterRole.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: p.serviceAccount.metadata.name,
      namespace: p._config.namespace,
    }],
  },

  roleSpecificNamespaces:
    local newSpecificRole(namespace) = {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: p._metadata {
        namespace: namespace,
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
    apiVersion: 'policy/v1',
    kind: 'PodDisruptionBudget',
    metadata: p._metadata,
    spec: {
      minAvailable: 1,
      selector: {
        matchLabels: p._config.selectorLabels,
      },
    },
  },

  prometheus: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'Prometheus',
    metadata: p._metadata {
      name: p._config.name,
    },
    spec: {
      #replicas: p._config.replicas,
      replicas: environment_vars.kube_prometheus.replicas.prometheusK8s,
      version: p._config.version,
      image: p._config.image,
      podMetadata: {
        labels: p.prometheus.metadata.labels,
      },
      externalLabels: p._config.externalLabels,
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
      serviceAccountName: p.serviceAccount.metadata.name,
      podMonitorSelector: {},
      podMonitorNamespaceSelector: {},
      probeSelector: {},
      probeNamespaceSelector: {},
      ruleNamespaceSelector: {},
      ruleSelector: p._config.ruleSelector,
      scrapeConfigSelector: {},
      scrapeConfigNamespaceSelector: {},
      serviceMonitorSelector: p._metadata,,
      serviceMonitorNamespaceSelector: {},
      nodeSelector: { 'kubernetes.io/os': 'linux' },
      resources: p._config.resources,
      alerting: if p._config.alerting != {} then p._config.alerting else {
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
    metadata: p._metadata,
    spec: {
      jobLabel: 'app.kubernetes.io/name',
      selector: {
        matchLabels: p._metadata,
      },
      endpoints: [
        { port: 'web', interval: p._config.scrapeInterval },
        { port: 'reloader-web', interval: p._config.scrapeInterval },
      ],     
    },
  },

  // Include thanos sidecar PrometheusRule only if thanos config was passed by user
  [if std.objectHas(params, 'thanos') && params.thanos != null then 'prometheusRuleThanosSidecar']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: p._metadata {
      labels+: p._config.mixin.ruleLabels,
      name: p._metadata.name + '-thanos-sidecar-rules',
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
    metadata+: p._metadata {
      name: p._metadata.name + '-thanos-sidecar',
      labels+: {
        'app.kubernetes.io/component': 'thanos-sidecar',
      },
    },
    spec+: {
      ports: [
        { name: 'grpc', port: 10901, targetPort: 10901 },
        { name: 'http', port: 10902, targetPort: 10902 },
      ],
      selector: p._config.selectorLabels {
        'app.kubernetes.io/component': 'prometheus',
      },
      clusterIP: 'None',
    },
  },

  // Include thanos sidecar ServiceMonitor only if thanos config was passed by user
  [if std.objectHas(params, 'thanos') && params.thanos != null then 'serviceMonitorThanosSidecar']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: p._metadata {
      name: 'thanos-sidecar',
      labels+: {
        'app.kubernetes.io/component': 'thanos-sidecar',
      },
    },
    spec+: {
      jobLabel: 'app.kubernetes.io/component',
      selector: {
        matchLabels: {
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
