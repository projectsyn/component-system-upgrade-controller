// main template for system-upgrade-controller
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.system_upgrade_controller;

local namespace = kube.Namespace(params.namespace);

local serviceaccount = kube.ServiceAccount('system-upgrade') {
  metadata+: {
      namespace: params.namespace
  },
};

local clusterrolebinding = kube.ClusterRoleBinding('system-upgrade') {
  metadata+: {
      namespace: params.namespace
  },
  roleRef+: {
    apiGroup: "rbac.authorization.k8s.io",
    kind: "ClusterRole",
    name: "cluster-admin"
  },
  subjects_: [serviceaccount],
};

local configmap = kube.ConfigMap('default-controller-env') {
  metadata+: {
      namespace: params.namespace
  },
  data+: {
    "SYSTEM_UPGRADE_CONTROLLER_DEBUG": params.debug_logging,
    "SYSTEM_UPGRADE_CONTROLLER_THREADS": params.controller_threads,
    "SYSTEM_UPGRADE_JOB_ACTIVE_DEADLINE_SECONDS": params.job_deadline_seconds,
    "SYSTEM_UPGRADE_JOB_BACKOFF_LIMIT": params.backoff_limit,
    "SYSTEM_UPGRADE_JOB_IMAGE_PULL_POLICY": params.job_image_pull_policy,
    "SYSTEM_UPGRADE_JOB_KUBECTL_IMAGE": params.job_kubectl_image,
    "SYSTEM_UPGRADE_JOB_PRIVILEGED": params.job_privileged,
    "SYSTEM_UPGRADE_JOB_TTL_SECONDS_AFTER_FINISH": params.job_ttl_after_finish,
    "SYSTEM_UPGRADE_PLAN_POLLING_INTERVAL": params.plan_polling_interval
  }
};

local extraVols =
  if inv.parameters.cluster.dist == 'eks' then
    [{
      hostPath: {
        path: '/etc/pki',
        type: 'Directory',
      },
      name: 'etc-pki',
    }]
  else
    [];
local extraVolMounts =
  if inv.parameters.cluster.dist == 'eks' then
    [{
      mountPath: "/etc/pki",
      name: "etc-pki",
    }]
  else
    [];

local affinity =
  if inv.parameters.cluster.dist == 'eks' then
    {}
  else
    {
      nodeAffinity: {
        requiredDuringSchedulingIgnoredDuringExecution: {
          nodeSelectorTerms: [
            {
              matchExpressions: [
                {
                  key: "node-role.kubernetes.io/master",
                  operator: "In",
                  values: [
                    "true"
                  ]
                }
              ]
            }
          ]
        }
      }
    };
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
        "upgrade.cattle.io/controller": "system-upgrade-controller"
      }
    },
    template+: {
      metadata: {
        labels: {
          "upgrade.cattle.io/controller": "system-upgrade-controller"
        }
      },
      spec+: {
        affinity: affinity,
        containers: [
          {
            env: [
              {
                name: "SYSTEM_UPGRADE_CONTROLLER_NAME",
                valueFrom: {
                  fieldRef: {
                    fieldPath: "metadata.labels['upgrade.cattle.io/controller']"
                  }
                }
              },
              {
                name: "SYSTEM_UPGRADE_CONTROLLER_NAMESPACE",
                valueFrom: {
                  fieldRef: {
                    fieldPath: "metadata.namespace"
                  }
                }
              }
            ],
            envFrom: [
              {
                configMapRef: {
                  name: "default-controller-env"
                }
              }
            ],
            image: params.suc_image,
            imagePullPolicy: "IfNotPresent",
            name: "system-upgrade-controller",
            resources+: {
              requests: {
                memory: "64Mi",
                cpu: "250m",
              },
              limits: {
                memory: "128Mi",
                cpu: "500m",
              },
            },
            volumeMounts: [
              {
                mountPath: "/etc/ssl",
                name: "etc-ssl"
              },
              {
                mountPath: "/tmp",
                name: "tmp"
              }
            ] + extraVolMounts,
          }
        ],
        serviceAccountName: "system-upgrade",
        volumes: [
          {
            hostPath: {
              path: "/etc/ssl",
              type: "Directory"
            },
            name: "etc-ssl"
          },
          {
            emptyDir: {},
            name: "tmp"
          }
        ] + extraVols,
      },
    },
  },
};

local plan = [

  local channel = (
    if std.objectHas(p, 'channel') then [
      p.channel
    ] else [
      params.floodgate_url+p.day+"/"+p.hour
    ]
  );

  suc.Plan(p.name, channel, p.label_selectors, p.concurrency, p.image, p.push_gateway, p.command)
  for p in params.plans
];

local dashboard = {
  "apiVersion": "integreatly.org/v1alpha1",
  "kind": "GrafanaDashboard",
  "metadata": {
      "name": "system-upgrade-controller",
      "namespace": inv.parameters.synsights.namespace,
      "labels": {
          "app": "platform-grafana"
      }
  },
  "spec": {
      "name": "syste-upgrade-controller.json",
      "json": "{\n  \"annotations\": {\n    \"list\": [\n      {\n        \"builtIn\": 1,\n        \"datasource\": \"-- Grafana --\",\n        \"enable\": true,\n        \"hide\": true,\n        \"iconColor\": \"rgba(0, 211, 255, 1)\",\n        \"name\": \"Annotations & Alerts\",\n        \"type\": \"dashboard\"\n      }\n    ]\n  },\n  \"editable\": true,\n  \"gnetId\": null,\n  \"graphTooltip\": 0,\n  \"id\": 3,\n  \"links\": [],\n  \"panels\": [\n    {\n      \"aliasColors\": {\n        \"Jobs failed\": \"dark-red\",\n        \"Nodes completed\": \"dark-green\",\n        \"Running Jobs\": \"dark-purple\"\n      },\n      \"bars\": false,\n      \"dashLength\": 10,\n      \"dashes\": false,\n      \"datasource\": \"RANCHER_MONITORING\",\n      \"fill\": 1,\n      \"fillGradient\": 0,\n      \"gridPos\": {\n        \"h\": 9,\n        \"w\": 12,\n        \"x\": 0,\n        \"y\": 0\n      },\n      \"hiddenSeries\": false,\n      \"id\": 2,\n      \"legend\": {\n        \"avg\": false,\n        \"current\": false,\n        \"max\": false,\n        \"min\": false,\n        \"show\": true,\n        \"total\": false,\n        \"values\": false\n      },\n      \"lines\": true,\n      \"linewidth\": 1,\n      \"nullPointMode\": \"null as zero\",\n      \"options\": {\n        \"dataLinks\": []\n      },\n      \"percentage\": false,\n      \"pointradius\": 2,\n      \"points\": false,\n      \"renderer\": \"flot\",\n      \"seriesOverrides\": [],\n      \"spaceLength\": 10,\n      \"stack\": false,\n      \"steppedLine\": false,\n      \"targets\": [\n        {\n          \"expr\": \"count(kube_job_status_succeeded{namespace=\\\"syn-system-upgrade-controller\\\"} == 1) by (node)\",\n          \"instant\": false,\n          \"interval\": \"\",\n          \"legendFormat\": \"Nodes completed\",\n          \"refId\": \"A\"\n        },\n        {\n          \"expr\": \"sum(kube_node_info)\",\n          \"instant\": false,\n          \"interval\": \"\",\n          \"legendFormat\": \"Nodes\",\n          \"refId\": \"B\"\n        },\n        {\n          \"expr\": \"count(kube_job_status_failed{namespace=\\\"syn-system-upgrade-controller\\\"} > 1) by (node) \",\n          \"interval\": \"\",\n          \"legendFormat\": \"Jobs failed\",\n          \"refId\": \"C\"\n        },\n        {\n          \"expr\": \"sum(kube_job_status_active{namespace=\\\"syn-system-upgrade-controller\\\"} == 1) by (node)\",\n          \"interval\": \"\",\n          \"legendFormat\": \"Running Jobs\",\n          \"refId\": \"D\"\n        }\n      ],\n      \"thresholds\": [],\n      \"timeFrom\": null,\n      \"timeRegions\": [],\n      \"timeShift\": null,\n      \"title\": \"Upgrade Jobs completed\",\n      \"tooltip\": {\n        \"shared\": true,\n        \"sort\": 0,\n        \"value_type\": \"individual\"\n      },\n      \"type\": \"graph\",\n      \"xaxis\": {\n        \"buckets\": null,\n        \"mode\": \"time\",\n        \"name\": null,\n        \"show\": true,\n        \"values\": []\n      },\n      \"yaxes\": [\n        {\n          \"format\": \"short\",\n          \"label\": null,\n          \"logBase\": 1,\n          \"max\": null,\n          \"min\": \"0\",\n          \"show\": true\n        },\n        {\n          \"format\": \"short\",\n          \"label\": null,\n          \"logBase\": 1,\n          \"max\": null,\n          \"min\": null,\n          \"show\": true\n        }\n      ],\n      \"yaxis\": {\n        \"align\": false,\n        \"alignLevel\": null\n      }\n    },\n    {\n      \"aliasColors\": {\n        \"Cordoned nodes\": \"dark-red\",\n        \"Total nodes\": \"green\"\n      },\n      \"bars\": false,\n      \"dashLength\": 10,\n      \"dashes\": false,\n      \"datasource\": \"RANCHER_MONITORING\",\n      \"fill\": 1,\n      \"fillGradient\": 0,\n      \"gridPos\": {\n        \"h\": 9,\n        \"w\": 12,\n        \"x\": 12,\n        \"y\": 0\n      },\n      \"hiddenSeries\": false,\n      \"id\": 4,\n      \"legend\": {\n        \"avg\": false,\n        \"current\": false,\n        \"max\": false,\n        \"min\": false,\n        \"show\": true,\n        \"total\": false,\n        \"values\": false\n      },\n      \"lines\": true,\n      \"linewidth\": 1,\n      \"nullPointMode\": \"null\",\n      \"options\": {\n        \"dataLinks\": []\n      },\n      \"percentage\": false,\n      \"pointradius\": 2,\n      \"points\": false,\n      \"renderer\": \"flot\",\n      \"seriesOverrides\": [],\n      \"spaceLength\": 10,\n      \"stack\": false,\n      \"steppedLine\": false,\n      \"targets\": [\n        {\n          \"expr\": \"sum(kube_node_spec_unschedulable)\",\n          \"interval\": \"\",\n          \"legendFormat\": \"Cordoned nodes\",\n          \"refId\": \"A\"\n        },\n        {\n          \"expr\": \"count(kube_node_info)\",\n          \"interval\": \"\",\n          \"legendFormat\": \"Total nodes\",\n          \"refId\": \"B\"\n        }\n      ],\n      \"thresholds\": [],\n      \"timeFrom\": null,\n      \"timeRegions\": [],\n      \"timeShift\": null,\n      \"title\": \"Cordoned Nodes\",\n      \"tooltip\": {\n        \"shared\": true,\n        \"sort\": 0,\n        \"value_type\": \"individual\"\n      },\n      \"type\": \"graph\",\n      \"xaxis\": {\n        \"buckets\": null,\n        \"mode\": \"time\",\n        \"name\": null,\n        \"show\": true,\n        \"values\": []\n      },\n      \"yaxes\": [\n        {\n          \"format\": \"short\",\n          \"label\": null,\n          \"logBase\": 1,\n          \"max\": null,\n          \"min\": null,\n          \"show\": true\n        },\n        {\n          \"format\": \"short\",\n          \"label\": null,\n          \"logBase\": 1,\n          \"max\": null,\n          \"min\": null,\n          \"show\": true\n        }\n      ],\n      \"yaxis\": {\n        \"align\": false,\n        \"alignLevel\": null\n      }\n    },\n    {\n      \"columns\": [],\n      \"datasource\": \"RANCHER_MONITORING\",\n      \"fontSize\": \"100%\",\n      \"gridPos\": {\n        \"h\": 8,\n        \"w\": 12,\n        \"x\": 0,\n        \"y\": 9\n      },\n      \"hideTimeOverride\": false,\n      \"id\": 6,\n      \"interval\": \"\",\n      \"options\": {},\n      \"pageSize\": null,\n      \"repeat\": null,\n      \"showHeader\": true,\n      \"sort\": {\n        \"col\": 15,\n        \"desc\": true\n      },\n      \"styles\": [\n        {\n          \"alias\": \"Node Hashes\",\n          \"align\": \"left\",\n          \"colorMode\": null,\n          \"colors\": [\n            \"rgba(245, 54, 54, 0.9)\",\n            \"rgba(237, 129, 40, 0.89)\",\n            \"rgba(50, 172, 45, 0.97)\"\n          ],\n          \"decimals\": 2,\n          \"link\": false,\n          \"mappingType\": 1,\n          \"pattern\": \"Metric\",\n          \"preserveFormat\": false,\n          \"rangeMaps\": [],\n          \"sanitize\": false,\n          \"thresholds\": [],\n          \"type\": \"string\",\n          \"unit\": \"short\",\n          \"valueMaps\": []\n        },\n        {\n          \"alias\": \"\",\n          \"align\": \"auto\",\n          \"colorMode\": null,\n          \"colors\": [\n            \"rgba(245, 54, 54, 0.9)\",\n            \"rgba(237, 129, 40, 0.89)\",\n            \"rgba(50, 172, 45, 0.97)\"\n          ],\n          \"dateFormat\": \"YYYY-MM-DD HH:mm:ss\",\n          \"decimals\": 2,\n          \"mappingType\": 1,\n          \"pattern\": \"Time\",\n          \"thresholds\": [],\n          \"type\": \"hidden\",\n          \"unit\": \"short\"\n        },\n        {\n          \"alias\": \"\",\n          \"colorMode\": null,\n          \"colors\": [\n            \"rgba(245, 54, 54, 0.9)\",\n            \"rgba(237, 129, 40, 0.89)\",\n            \"rgba(50, 172, 45, 0.97)\"\n          ],\n          \"dateFormat\": \"YYYY-MM-DD HH:mm:ss\",\n          \"decimals\": 2,\n          \"mappingType\": 1,\n          \"pattern\": \"/label_k3s:*|Value|kubernetes_.*|__name__|instance|app_kubernetes_io_.*|job|helm.*/\",\n          \"thresholds\": [],\n          \"type\": \"hidden\",\n          \"unit\": \"short\"\n        },\n        {\n          \"alias\": \"Node\",\n          \"colorMode\": null,\n          \"colors\": [\n            \"rgba(245, 54, 54, 0.9)\",\n            \"rgba(237, 129, 40, 0.89)\",\n            \"rgba(50, 172, 45, 0.97)\"\n          ],\n          \"dateFormat\": \"YYYY-MM-DD HH:mm:ss\",\n          \"decimals\": 2,\n          \"mappingType\": 1,\n          \"pattern\": \"node\",\n          \"thresholds\": [],\n          \"type\": \"number\",\n          \"unit\": \"short\"\n        },\n        {\n          \"alias\": \"Upgrade Hash\",\n          \"colorMode\": null,\n          \"colors\": [\n            \"rgba(245, 54, 54, 0.9)\",\n            \"rgba(237, 129, 40, 0.89)\",\n            \"rgba(50, 172, 45, 0.97)\"\n          ],\n          \"dateFormat\": \"YYYY-MM-DD HH:mm:ss\",\n          \"decimals\": 2,\n          \"mappingType\": 1,\n          \"pattern\": \"/label_plan_upgrade_cattle_io_.*/\",\n          \"thresholds\": [],\n          \"type\": \"string\",\n          \"unit\": \"short\"\n        },\n        {\n          \"alias\": \"\",\n          \"colorMode\": null,\n          \"colors\": [\n            \"rgba(245, 54, 54, 0.9)\",\n            \"rgba(237, 129, 40, 0.89)\",\n            \"rgba(50, 172, 45, 0.97)\"\n          ],\n          \"dateFormat\": \"YYYY-MM-DD HH:mm:ss\",\n          \"decimals\": 2,\n          \"mappingType\": 1,\n          \"pattern\": \"/.*/\",\n          \"thresholds\": [],\n          \"type\": \"string\",\n          \"unit\": \"short\"\n        }\n      ],\n      \"targets\": [\n        {\n          \"expr\": \"kube_node_labels\",\n          \"format\": \"table\",\n          \"hide\": false,\n          \"instant\": true,\n          \"interval\": \"\",\n          \"intervalFactor\": 1,\n          \"legendFormat\": \"\",\n          \"refId\": \"A\"\n        }\n      ],\n      \"timeFrom\": null,\n      \"timeShift\": null,\n      \"title\": \"Node table\",\n      \"transform\": \"table\",\n      \"type\": \"table\"\n    },\n    {\n      \"columns\": [],\n      \"datasource\": \"RANCHER_MONITORING\",\n      \"fontSize\": \"100%\",\n      \"gridPos\": {\n        \"h\": 8,\n        \"w\": 12,\n        \"x\": 12,\n        \"y\": 9\n      },\n      \"id\": 8,\n      \"options\": {},\n      \"pageSize\": null,\n      \"showHeader\": true,\n      \"sort\": {\n        \"col\": 0,\n        \"desc\": true\n      },\n      \"styles\": [\n        {\n          \"alias\": \"Time\",\n          \"dateFormat\": \"YYYY-MM-DD HH:mm:ss\",\n          \"pattern\": \"Time\",\n          \"type\": \"hidden\"\n        },\n        {\n          \"alias\": \"\",\n          \"colorMode\": null,\n          \"colors\": [\n            \"rgba(245, 54, 54, 0.9)\",\n            \"rgba(237, 129, 40, 0.89)\",\n            \"rgba(50, 172, 45, 0.97)\"\n          ],\n          \"dateFormat\": \"YYYY-MM-DD HH:mm:ss\",\n          \"decimals\": 2,\n          \"mappingType\": 1,\n          \"pattern\": \"Value\",\n          \"thresholds\": [],\n          \"type\": \"hidden\",\n          \"unit\": \"short\"\n        },\n        {\n          \"alias\": \"\",\n          \"colorMode\": null,\n          \"colors\": [\n            \"rgba(245, 54, 54, 0.9)\",\n            \"rgba(237, 129, 40, 0.89)\",\n            \"rgba(50, 172, 45, 0.97)\"\n          ],\n          \"dateFormat\": \"YYYY-MM-DD HH:mm:ss\",\n          \"decimals\": 2,\n          \"mappingType\": 1,\n          \"pattern\": \"/__name__|endpoint|job|namespace|pod|service/\",\n          \"thresholds\": [],\n          \"type\": \"hidden\",\n          \"unit\": \"short\"\n        },\n        {\n          \"alias\": \"\",\n          \"colorMode\": null,\n          \"colors\": [\n            \"rgba(245, 54, 54, 0.9)\",\n            \"rgba(237, 129, 40, 0.89)\",\n            \"rgba(50, 172, 45, 0.97)\"\n          ],\n          \"decimals\": 2,\n          \"pattern\": \"/.*/\",\n          \"thresholds\": [],\n          \"type\": \"number\",\n          \"unit\": \"short\"\n        }\n      ],\n      \"targets\": [\n        {\n          \"expr\": \"suc_package_upgraded\",\n          \"format\": \"table\",\n          \"instant\": true,\n          \"refId\": \"A\"\n        }\n      ],\n      \"timeFrom\": null,\n      \"timeShift\": null,\n      \"title\": \"Updated Packages\",\n      \"transform\": \"table\",\n      \"type\": \"table\"\n    }\n  ],\n  \"refresh\": \"5s\",\n  \"schemaVersion\": 21,\n  \"style\": \"dark\",\n  \"tags\": [],\n  \"templating\": {\n    \"list\": []\n  },\n  \"time\": {\n    \"from\": \"now-1h\",\n    \"to\": \"now\"\n  },\n  \"timepicker\": {\n    \"refresh_intervals\": [\n      \"5s\",\n      \"10s\",\n      \"30s\",\n      \"1m\",\n      \"5m\",\n      \"15m\",\n      \"30m\",\n      \"1h\",\n      \"2h\",\n      \"1d\"\n    ]\n  },\n  \"timezone\": \"\",\n  \"title\": \"SUC overview\",\n  \"uid\": \"Ut3fVneZz\",\n  \"version\": 1\n}"
  }
};

// Define outputs below
{
  '00_namespace': namespace,
  '01_serviceaccount': serviceaccount,
  '02_clusterrolebinding': clusterrolebinding,
  '03_configmap': configmap,
  '04_deployment': deployment,
  '05_plans': plan,
  [if !params.disable_grafana_dashboard then '06_dashboard']: dashboard,
}
