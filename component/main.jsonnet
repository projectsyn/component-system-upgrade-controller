// main template for system-upgrade-controller
local dashboard = import 'grafana_dashboard.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local suc = import 'lib/suc.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.system_upgrade_controller;

local namespace = kube.Namespace(params.namespace);

local serviceaccount = kube.ServiceAccount('system-upgrade') {
  metadata+: {
    namespace: params.namespace,
  },
};

local clusterrolebinding = kube.ClusterRoleBinding('system-upgrade') {
  metadata+: {
    namespace: params.namespace,
  },
  roleRef+: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: 'cluster-admin',
  },
  subjects_: [ serviceaccount ],
};

local configmap = kube.ConfigMap('default-controller-env') {
  metadata+: {
    namespace: params.namespace,
  },
  data+: {
    SYSTEM_UPGRADE_CONTROLLER_DEBUG: params.debug_logging,
    SYSTEM_UPGRADE_CONTROLLER_THREADS: params.controller_threads,
    SYSTEM_UPGRADE_JOB_ACTIVE_DEADLINE_SECONDS: params.job_deadline_seconds,
    SYSTEM_UPGRADE_JOB_BACKOFF_LIMIT: params.job_backoff_limit,
    SYSTEM_UPGRADE_JOB_IMAGE_PULL_POLICY: params.job_image_pull_policy,
    SYSTEM_UPGRADE_JOB_KUBECTL_IMAGE: params.job_kubectl_image,
    SYSTEM_UPGRADE_JOB_PRIVILEGED: params.job_privileged,
    SYSTEM_UPGRADE_JOB_TTL_SECONDS_AFTER_FINISH: params.job_ttl_after_finish,
    SYSTEM_UPGRADE_PLAN_POLLING_INTERVAL: params.plan_polling_interval,
  },
};

local extraVols =
  if inv.parameters.facts.distribution == 'eks' then
    [ {
      hostPath: {
        path: '/etc/pki',
        type: 'Directory',
      },
      name: 'etc-pki',
    } ]
  else
    [];
local extraVolMounts =
  if inv.parameters.facts.distribution == 'eks' then
    [ {
      mountPath: '/etc/pki',
      name: 'etc-pki',
    } ]
  else
    [];

local deployment = kube.Deployment('system-upgrade-controller') {
  metadata+: {
    namespace: params.namespace,
    labels+: {
      'app.kubernetes.io/name': 'system-upgrade-controller',
      'app.kubernetes.io/instance': inv.parameters.cluster.name,
      'app.kubernetes.io/managed-by': 'syn',
    },
  },
  spec+: {
    selector: {
      matchLabels: {
        'upgrade.cattle.io/controller': 'system-upgrade-controller',
      },
    },
    template+: {
      metadata: {
        labels: {
          'upgrade.cattle.io/controller': 'system-upgrade-controller',
        },
      },
      spec+: {
        affinity: params.affinity,
        containers: [
          kube.Container('system-upgrade-controller') {
            env_: com.proxyVars {
              SYSTEM_UPGRADE_CONTROLLER_NAME: {
                fieldRef: {
                  fieldPath: "metadata.labels['upgrade.cattle.io/controller']",
                },
              },
              SYSTEM_UPGRADE_CONTROLLER_NAMESPACE: {
                fieldRef: {
                  fieldPath: 'metadata.namespace',
                },
              },
            },
            envFrom: [
              {
                configMapRef: {
                  name: 'default-controller-env',
                },
              },
            ],
            image: params.suc_image,
            imagePullPolicy: 'IfNotPresent',
            resources+: {
              requests: {
                memory: '64Mi',
                cpu: '250m',
              },
              limits: {
                memory: '128Mi',
                cpu: '500m',
              },
            },
            volumeMounts: [
              {
                mountPath: '/etc/ssl',
                name: 'etc-ssl',
              },
              {
                mountPath: '/tmp',
                name: 'tmp',
              },
            ] + extraVolMounts,
          },
        ],
        serviceAccountName: 'system-upgrade',
        volumes: [
          {
            hostPath: {
              path: '/etc/ssl',
              type: 'Directory',
            },
            name: 'etc-ssl',
          },
          {
            emptyDir: {},
            name: 'tmp',
          },
        ] + extraVols,
      },
    },
  },
};

local plan = [

  local channel = (
    if std.objectHas(p, 'channel') then
      p.channel
    else
      params.floodgate_url + 'window/' + p.day + '/' + p.hour
  );

  local args(p) =
    if std.objectHas(p, 'args') then (
      if std.type(p.args) == 'array' then
        if std.objectHas(p, 'push_gateway') then
          std.prune(p.args + [ p.push_gateway ])
        else
          p.args
      else
        error 'Field `args` of plan "%(name)s" is not an array' % p
    ) else (
      if std.objectHas(p, 'push_gateway') then
        [ p.push_gateway ]
      else
        null
    );

  local command(p) =
    if std.objectHas(p, 'command') then (
      if std.type(p.command) == 'string' then (
        [ p.command ]
      )
      else (
        if std.type(p.command) == 'array' then (
          p.command
        ) else
          error 'Field `command` of plan "%(name)s" is not an array nor a string' % p
      )
    ) else
      null;

  local version = if std.objectHas(p, 'version') then p.version;

  suc.Plan(p.name, channel, version, p.label_selectors, p.concurrency, p.tolerations, p.image, command(p), args(p))
  for p in params.plans
];

// Define outputs below
{
  '00_namespace': namespace,
  '01_serviceaccount': serviceaccount,
  '02_clusterrolebinding': clusterrolebinding,
  '03_configmap': configmap,
  '04_deployment': deployment,
  '05_plans': plan,
  [if !params.disable_grafana_dashboard then '06_dashboard']: dashboard.dashboard,
}
