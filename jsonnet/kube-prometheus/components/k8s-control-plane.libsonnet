local relabelings = import '../addons/dropping-deprecated-metrics-relabelings.libsonnet';

local defaults = {
  namespace: error 'must provide namespace',
  commonLabels:: {
    'app.kubernetes.io/name': 'kube-prometheus',
    'app.kubernetes.io/part-of': 'kube-prometheus',
  },
  mixin: {
    ruleLabels: {},
    _config: {
      cadvisorSelector: 'job="kubelet", metrics_path="/metrics/cadvisor"',
      kubeletSelector: 'job="kubelet", metrics_path="/metrics"',
      kubeStateMetricsSelector: 'job="kube-state-metrics"',
      nodeExporterSelector: 'job="node-exporter"',
      kubeSchedulerSelector: 'job="kube-scheduler"',
      kubeControllerManagerSelector: 'job="kube-controller-manager"',
      kubeApiserverSelector: 'job="apiserver"',
      podLabel: 'pod',
      runbookURLPattern: 'https://runbooks.prometheus-operator.dev/runbooks/kubernetes/%s',
      diskDeviceSelector: 'device=~"mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|dasd.+"',
      hostNetworkInterfaceSelector: 'device!~"veth.+"',
    },
  },
  kubeProxy: false,
};

function(params) {
  local k8s = self,
  _config:: defaults + params,

  mixin:: (import 'github.com/kubernetes-monitoring/kubernetes-mixin/mixin.libsonnet') {
    _config+:: k8s._config.mixin._config,
  },

  prometheusRule: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: {
      labels: k8s._config.commonLabels + k8s._config.mixin.ruleLabels,
      name: 'kubernetes-monitoring-rules',
      namespace: k8s._config.namespace,
    },
    spec: {
      local r = if std.objectHasAll(k8s.mixin, 'prometheusRules') then k8s.mixin.prometheusRules.groups else {},
      local a = if std.objectHasAll(k8s.mixin, 'prometheusAlerts') then k8s.mixin.prometheusAlerts.groups else {},
      groups: a + r,
    },
  },

  serviceMonitorKubeScheduler: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: {
      name: 'kube-scheduler',
      namespace: k8s._config.namespace,
      labels: { 'app.kubernetes.io/name': 'kube-scheduler' },
    },
    spec: {
      jobLabel: 'app.kubernetes.io/name',
      endpoints: [{
        port: 'https-metrics',
        interval: '2m',
        scheme: 'https',
        bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
        tlsConfig: { insecureSkipVerify: true },
      }],
      selector: {
        matchLabels: { 'app.kubernetes.io/name': 'kube-scheduler' },
      },
      namespaceSelector: {
        matchNames: ['kube-system'],
      },
    },
  },

  serviceMonitorKubelet: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: {
      name: 'kubelet',
      namespace: k8s._config.namespace,
      labels: { 'app.kubernetes.io/name': 'kubelet' },
    },
    spec: {
      jobLabel: 'app.kubernetes.io/name',
      endpoints: [
        {
          port: 'https-metrics',
          scheme: 'https',
          interval: '2m',
          honorLabels: true,
          tlsConfig: { insecureSkipVerify: true },
          bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
          metricRelabelings: [
            // Drop a bunch of metrics which are disabled but still sent, see
            // https://github.com/google/cadvisor/issues/1925.
            {
              sourceLabels: ['__name__'],
              regex: 'container_(network_tcp_usage_total|network_udp_usage_total|tasks_state|cpu_load_average_10s)',
              action: 'drop',
            },
            // Drop cAdvisor metrics with no (pod, namespace) labels while preserving ability to monitor system services resource usage (cardinality estimation)
            {
              sourceLabels: ['__name__', 'pod', 'namespace'],
              action: 'drop',
              regex: '(' + std.join('|',
                                    [
                                      'container_spec_.*',  // everything related to cgroup specification and thus static data (nodes*services*5)
                                      'container_file_descriptors',  // file descriptors limits and global numbers are exposed via (nodes*services)
                                      'container_sockets',  // used sockets in cgroup. Usually not important for system services (nodes*services)
                                      'container_threads_max',  // max number of threads in cgroup. Usually for system services it is not limited (nodes*services)
                                      'container_threads',  // used threads in cgroup. Usually not important for system services (nodes*services)
                                      'container_start_time_seconds',  // container start. Possibly not needed for system services (nodes*services)
                                      'container_last_seen',  // not needed as system services are always running (nodes*services)
                                    ]) + ');;',
            },
            {
              sourceLabels: ['__name__', 'container'],
              action: 'drop',
              regex: '(' + std.join('|',
                                    [
                                      'container_blkio_device_usage_total',
                                    ]) + ');.+',
            },
            {
              sourceLabels: ['__name__'],
              regex: 'aggregator_.*|apiserver_.*|authentication_.*|csi_operations_.*|force_cleaned_failed_.*|get_token_.*|machine_.*|node_namespace_.*|plugin_manager_.*|prober_probe_.*|reconstruct_volume_.*|rest_client_.*|storage_operation_.*|volume_.*|workqueue_.*|go_.*',
              action: 'drop',
            },
            {
              sourceLabels: ['__name__'],
              regex: 'kubelet_(cgroup|container|cpu|evented|eviction|graceful|http|lifecycle|orphan|pleg|pod|run|runtime|topology)_.*',
              action: 'drop',
            },
          ],
          relabelings: [{
            sourceLabels: ['__metrics_path__'],
            targetLabel: 'metrics_path',
          }],
        },
        {
          port: 'https-metrics',
          scheme: 'https',
          path: '/metrics/cadvisor',
          interval: '2m',
          honorLabels: true,
          honorTimestamps: false,
          tlsConfig: {
            insecureSkipVerify: true,
          },
          bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
          relabelings: [{
            sourceLabels: ['__metrics_path__'],
            targetLabel: 'metrics_path',
          }],
          metricRelabelings: [
            // Drop a bunch of metrics which are disabled but still sent, see
            // https://github.com/google/cadvisor/issues/1925.
            {
              sourceLabels: ['__name__'],
              regex: 'container_(network_tcp_usage_total|network_udp_usage_total|tasks_state|cpu_load_average_10s)',
              action: 'drop',
            },
            // Drop cAdvisor metrics with no (pod, namespace) labels while preserving ability to monitor system services resource usage (cardinality estimation)
            {
              sourceLabels: ['__name__', 'pod', 'namespace'],
              action: 'drop',
              regex: '(' + std.join('|',
                                    [
                                      'container_spec_.*',  // everything related to cgroup specification and thus static data (nodes*services*5)
                                      'container_file_descriptors',  // file descriptors limits and global numbers are exposed via (nodes*services)
                                      'container_sockets',  // used sockets in cgroup. Usually not important for system services (nodes*services)
                                      'container_threads_max',  // max number of threads in cgroup. Usually for system services it is not limited (nodes*services)
                                      'container_threads',  // used threads in cgroup. Usually not important for system services (nodes*services)
                                      'container_start_time_seconds',  // container start. Possibly not needed for system services (nodes*services)
                                      'container_last_seen',  // not needed as system services are always running (nodes*services)
                                    ]) + ');;',
            },
            {
              sourceLabels: ['__name__', 'container'],
              action: 'drop',
              regex: '(' + std.join('|',
                                    [
                                      'container_blkio_device_usage_total',
                                    ]) + ');.+',
            },
            {
              sourceLabels: ['__name__'],
              regex: 'aggregator_.*|apiserver_.*|authentication_.*|csi_operations_.*|force_cleaned_failed_.*|get_token_.*|machine_.*|node_namespace_.*|plugin_manager_.*|prober_probe_.*|reconstruct_volume_.*|rest_client_.*|storage_operation_.*|volume_.*|workqueue_.*|go_.*',
              action: 'drop',
            },
            {
              sourceLabels: ['__name__'],
              regex: 'kubelet_(cgroup|container|cpu|evented|eviction|graceful|http|lifecycle|orphan|pleg|pod|run|runtime|topology)_.*',
              action: 'drop',
            },
          ],
        },
        {
          port: 'https-metrics',
          scheme: 'https',
          path: '/metrics/probes',
          interval: '2m',
          honorLabels: true,
          metricRelabelings: [
            // Drop a bunch of metrics which are disabled but still sent, see
            // https://github.com/google/cadvisor/issues/1925.
            {
              sourceLabels: ['__name__'],
              regex: 'container_(network_tcp_usage_total|network_udp_usage_total|tasks_state|cpu_load_average_10s)',
              action: 'drop',
            },
            // Drop cAdvisor metrics with no (pod, namespace) labels while preserving ability to monitor system services resource usage (cardinality estimation)
            {
              sourceLabels: ['__name__', 'pod', 'namespace'],
              action: 'drop',
              regex: '(' + std.join('|',
                                    [
                                      'container_spec_.*',  // everything related to cgroup specification and thus static data (nodes*services*5)
                                      'container_file_descriptors',  // file descriptors limits and global numbers are exposed via (nodes*services)
                                      'container_sockets',  // used sockets in cgroup. Usually not important for system services (nodes*services)
                                      'container_threads_max',  // max number of threads in cgroup. Usually for system services it is not limited (nodes*services)
                                      'container_threads',  // used threads in cgroup. Usually not important for system services (nodes*services)
                                      'container_start_time_seconds',  // container start. Possibly not needed for system services (nodes*services)
                                      'container_last_seen',  // not needed as system services are always running (nodes*services)
                                    ]) + ');;',
            },
            {
              sourceLabels: ['__name__', 'container'],
              action: 'drop',
              regex: '(' + std.join('|',
                                    [
                                      'container_blkio_device_usage_total',
                                    ]) + ');.+',
            },
            {
              sourceLabels: ['__name__'],
              regex: 'aggregator_.*|apiserver_.*|authentication_.*|csi_operations_.*|force_cleaned_failed_.*|get_token_.*|machine_.*|node_namespace_.*|plugin_manager_.*|prober_probe_.*|reconstruct_volume_.*|rest_client_.*|storage_operation_.*|volume_.*|workqueue_.*|go_.*',
              action: 'drop',
            },
            {
              sourceLabels: ['__name__'],
              regex: 'kubelet_(cgroup|container|cpu|evented|eviction|graceful|http|lifecycle|orphan|pleg|pod|run|runtime|topology)_.*',
              action: 'drop',
            },
          ],
          tlsConfig: { insecureSkipVerify: true },
          bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
          relabelings: [{
            sourceLabels: ['__metrics_path__'],
            targetLabel: 'metrics_path',
          }],
        },
      ],
      selector: {
        matchLabels: { 'app.kubernetes.io/name': 'kubelet' },
      },
      namespaceSelector: {
        matchNames: ['kube-system'],
      },
    },
  },

  serviceMonitorKubeControllerManager: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: {
      name: 'kube-controller-manager',
      namespace: k8s._config.namespace,
      labels: { 'app.kubernetes.io/name': 'kube-controller-manager' },
    },
    spec: {
      jobLabel: 'app.kubernetes.io/name',
      endpoints: [{
        port: 'https-metrics',
        interval: '2m',
        scheme: 'https',
        bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
        tlsConfig: {
          insecureSkipVerify: true,
        },
        metricRelabelings: relabelings + [
          {
            sourceLabels: ['__name__'],
            regex: 'etcd_(debugging|disk|request|server).*',
            action: 'drop',
          },
        ],
      }],
      selector: {
        matchLabels: { 'app.kubernetes.io/name': 'kube-controller-manager' },
      },
      namespaceSelector: {
        matchNames: ['kube-system'],
      },
    },
  },

  serviceMonitorApiserver: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: {
      name: 'kube-apiserver',
      namespace: k8s._config.namespace,
      labels: { 'app.kubernetes.io/name': 'apiserver' },
    },
    spec: {
      jobLabel: 'component',
      selector: {
        matchLabels: {
          component: 'apiserver',
          provider: 'kubernetes',
        },
      },
      namespaceSelector: {
        matchNames: ['default'],
      },
      endpoints: [{
        port: 'https',
        interval: '2m',
        scheme: 'https',
        tlsConfig: {
          caFile: '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
          serverName: 'kubernetes',
        },
        bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
        metricRelabelings: relabelings + [
          {
            sourceLabels: ['__name__'],
            regex: 'etcd_(debugging|disk|server).*',
            action: 'drop',
          },
          {
            sourceLabels: ['__name__'],
            regex: 'apiserver_admission_controller_admission_latencies_seconds_.*',
            action: 'drop',
          },
          {
            sourceLabels: ['__name__'],
            regex: 'apiserver_admission_step_admission_latencies_seconds_.*',
            action: 'drop',
          },
          {
            sourceLabels: ['__name__', 'le'],
            regex: 'apiserver_request_duration_seconds_bucket;(0.15|0.25|0.3|0.35|0.4|0.45|0.6|0.7|0.8|0.9|1.25|1.5|1.75|2.5|3|3.5|4.5|6|7|8|9|15|25|30|50)',
            action: 'drop',
          },
          {
            sourceLabels: ['__name__'],
            regex: 'aggregator_.*|apiextensions_.*|apiserver_.*|authenticated_.*|authentication_.*|etcd_.*|field_validation_request_.*|get_token_.*|grpc_client_.*|kube_apiserver_.*|node_authorizer_graph_.*|pod_security_.*|rest_client_.*|serviceaccount_.*|watch_cache_.*|workqueue_.*|go_.*',
            action: 'drop',
          },
        ],
      }],
    },
  },

  [if (defaults + params).kubeProxy then 'podMonitorKubeProxy']: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PodMonitor',
    metadata: {
      labels: {
        'k8s-app': 'kube-proxy',
      },
      name: 'kube-proxy',
      namespace: k8s._config.namespace,
    },
    spec: {
      jobLabel: 'k8s-app',
      namespaceSelector: {
        matchNames: [
          'kube-system',
        ],
      },
      selector: {
        matchLabels: {
          'k8s-app': 'kube-proxy',
        },
      },
      podMetricsEndpoints: [{
        honorLabels: true,
        relabelings: [
          {
            action: 'replace',
            regex: '(.*)',
            replacement: '$1',
            sourceLabels: ['__meta_kubernetes_pod_node_name'],
            targetLabel: 'instance',
          },
          {
            action: 'replace',
            regex: '(.*)',
            replacement: '$1:10249',
            targetLabel: '__address__',
            sourceLabels: ['__meta_kubernetes_pod_ip'],
          },
        ],
      }],
    },
  },


  serviceMonitorCoreDNS: {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: {
      name: 'coredns',
      namespace: k8s._config.namespace,
      labels: { 'app.kubernetes.io/name': 'coredns' },
    },
    spec: {
      jobLabel: 'app.kubernetes.io/name',
      selector: {
        matchLabels: { 'k8s-app': 'kube-dns' },
      },
      namespaceSelector: {
        matchNames: ['kube-system'],
      },
      endpoints: [{
        port: 'metrics',
        interval: '2m',
        bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
        metricRelabelings: [
          // Drop deprecated metrics
          // TODO (pgough) - consolidate how we drop metrics across the project
          {
            sourceLabels: ['__name__'],
            regex: 'coredns_cache_misses_total',
            action: 'drop',
          },
          {
            sourceLabels: ['__name__'],
            regex: 'coredns_.*|go_.*',
            action: 'drop',
          },
        ],
      }],
    },
  },


}
