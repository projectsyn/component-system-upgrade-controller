local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.system_upgrade_controller;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('system-upgrade-controller', params.namespace);

{
  'system-upgrade-controller': app,
}
