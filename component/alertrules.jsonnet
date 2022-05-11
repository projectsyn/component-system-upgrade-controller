local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.system_upgrade_controller;

local alert_rules =
  kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', 'system-upgrade-controller-alert-rules') {
    metadata+: {
      namespace: params.monitoring.prometheusRuleNamespace,
      labels+: {
        role: 'alert-rules',
        prometheus: 'platform',
      },
    },
    spec: {
      groups: [
        {
          name: 'system-upgrade-controller.rules',
          rules: [
            {
              alert: 'SYN_SystemUpgradeControllerMaintenanceHalted',
              expr: 'kube_node_spec_unschedulable >= 1',
              'for': '15m',
              labels: {
                severity: 'warning',
                syn: 'true',
                syn_component: 'system-upgrade-controller',
              },
              annotations: {
                message: 'Maintenance halted',
                description: 'system-upgrade-controller has stopped because the node {{ $labels.node }} cannot be drained. Check job logs for more information.',
                runbook_url: 'https://hub.syn.tools/systen-upgrade-controller/runbooks/SystemUpgradeControllerMaintenanceHalted.html',
                severity_level: 'warning',
              },
            },
          ],
        },
      ],
    },
  };

if params.monitoring.enabled then
  {
    '10_prometheusrule_system_upgrade_controller-alerts': alert_rules,
  }
else
  {}
