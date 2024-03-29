// main template for system-upgrade-controller
local dashboard = import 'grafana_dashboard.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local suc = import 'lib/system-upgrade-controller.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.system_upgrade_controller;

local sucImage =
  if std.objectHas(params, 'suc_image') then
    std.trace(
      (
        '\nParameter `suc_image` is deprecated.\n' +
        'Please update your config to use `images.system_upgrade_controller` instead.'
      ),
      params.suc_image
    )
  else
    '%(registry)s/%(repository)s:%(tag)s' % params.images.system_upgrade_controller;

local cattleSystemNamespaceNoPrune =
  if params.namespace == 'cattle-system' then
    {
      metadata+: {
        annotations+: {
          'argocd.argoproj.io/sync-options': 'Prune=false',
        },
      },
    }
  else
    {};

local namespace = kube.Namespace(params.namespace) +
                  cattleSystemNamespaceNoPrune;

local serviceaccount = kube.ServiceAccount(params.service_account) {
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
            image: sucImage,
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
        serviceAccountName: params.service_account,
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

local optionalKey(p, k) =
  if std.objectHas(p, k) then k;

local convertLegacyPlan(p) = std.trace(
  'Converting legacy SUC plan "%(name)s", please update your config' % p,
  {
    spec: {
      concurrency: p.concurrency,
      [optionalKey(p, 'channel')]: p.channel,
      [optionalKey(p, 'version')]: p.version,
      upgrade: {
        image: p.image,
        [optionalKey(p, 'command')]: p.command,
        // todo verify old structure
        [optionalKey(p, 'args')]: p.args,
      },
    },
    [optionalKey(p, 'push_gateway')]: p.push_gateway,
    label_selectors: {
      [l.key]: l
      for l in p.label_selectors
    },
    tolerations: {
      [t.key]: t
      for t in com.getValueOrDefault(p, 'tolerations', [])
    },
    floodgate: {
      day: p.day,
      hour: p.hour,
    },
  }
);

local planConfigs =
  if !std.objectHas(params, 'plans') then
    {}
  else if std.isArray(params.plans) then
    {
      [p.name]: convertLegacyPlan(p)
      for p in params.plans
    }
  else
    params.plans;

local plans = [
  local p = planConfigs[pname];
  local pspec = p.spec;

  local fixup_command(command) =
    if std.type(command) == 'string' then
      [ command ]
    else if std.type(command) == 'array' then
      command
    else
      error 'Field `spec.upgrade.command` of plan "%s" is not an array nor a string' % pname;

  local tolerations = com.getValueOrDefault(p, 'tolerations', {});

  local sp = suc.Plan(pname, p.label_selectors, tolerations) {
    spec+: com.makeMergeable(p.spec),
  };
  local needsFG = !std.objectHas(sp.spec, 'channel') && !std.objectHas(sp.spec, 'version');
  local hasCmd = std.objectHas(sp.spec, 'upgrade') && std.objectHas(sp.spec.upgrade, 'command');

  sp {
    spec+: {
      [if needsFG then 'channel']: suc.floodgate_channel(p.floodgate),
      upgrade+: {
        [if hasCmd then 'command']: fixup_command(super.command),
        [if std.objectHas(p, 'push_gateway') then 'args']+:
          [ p.push_gateway ],
      },
    },
  }

  for pname in std.sort(std.objectFields(planConfigs))
  if planConfigs[pname] != null
];

local controller_definition = {
  '00_namespace': namespace,
  '01_serviceaccount': serviceaccount,
  '02_clusterrolebinding': clusterrolebinding,
  '03_configmap': configmap,
  '04_deployment': deployment,
  [if !params.disable_grafana_dashboard then '06_dashboard']: dashboard.dashboard,
};

local plans_definition = {
  '05_plans': plans,
};

if params.plans_only then
  plans_definition
else
  controller_definition + plans_definition
