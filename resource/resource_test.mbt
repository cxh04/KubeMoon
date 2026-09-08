///|
test "core collection path is namespaced" {
  let pods = @resource.GroupVersionResource(
    group="",
    version="v1",
    resource="pods",
  )
  inspect(
    @resource.collection_path(pods, Namespace("team-a")),
    content="/api/v1/namespaces/team-a/pods",
  )
}

///|
test "grouped collection path can be cluster scoped" {
  let deployments = @resource.GroupVersionResource(
    group="apps",
    version="v1",
    resource="deployments",
  )
  inspect(
    @resource.collection_path(deployments, Cluster),
    content="/apis/apps/v1/deployments",
  )
}

///|
test "object path appends the resource name" {
  let config_maps = @resource.GroupVersionResource(
    group="",
    version="v1",
    resource="configmaps",
  )
  inspect(
    @resource.object_path(
      config_maps,
      Namespace("default"),
      "application-config",
    ),
    content="/api/v1/namespaces/default/configmaps/application-config",
  )
}
