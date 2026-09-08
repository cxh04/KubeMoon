///|
fn configmaps() -> @resource.GroupVersionResource {
  GroupVersionResource(group="", version="v1", resource="configmaps")
}

///|
test "build authenticated namespaced read requests" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example", bearer_token="secret"),
  )
  let list = client.list_request(configmaps(), Namespace("team-a"))
  inspect(list.verb().http_name(), content="GET")
  inspect(
    list.path(),
    content="https://cluster.example/api/v1/namespaces/team-a/configmaps",
  )
  inspect(list.header("authorization").unwrap_or(""), content="Bearer secret")
  inspect(list.header("accept").unwrap_or(""), content="application/json")

  let get = client.get_request(configmaps(), Namespace("team-a"), "settings")
  inspect(
    get.path(),
    content="https://cluster.example/api/v1/namespaces/team-a/configmaps/settings",
  )
}

///|
test "build create replace and delete requests" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example/"),
  )
  let create = client.create_request(
    configmaps(),
    Namespace("team-a"),
    "{\"metadata\":{\"name\":\"settings\"}}",
  )
  inspect(create.verb().http_name(), content="POST")
  inspect(
    create.header("content-type").unwrap_or(""),
    content="application/json",
  )

  let replace = client.replace_request(
    configmaps(),
    Namespace("team-a"),
    "settings",
    "{\"metadata\":{\"resourceVersion\":\"42\"}}",
  )
  inspect(replace.verb().http_name(), content="PUT")
  inspect(
    replace.body().unwrap_or(""),
    content="{\"metadata\":{\"resourceVersion\":\"42\"}}",
  )

  let delete = client.delete_request(
    configmaps(),
    Namespace("team-a"),
    "settings",
  )
  inspect(delete.verb().http_name(), content="DELETE")
  inspect(delete.body().unwrap_or(""), content="")
}

///|
test "select merge and JSON patch media types" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example"),
  )
  let merge = client.patch_request(
    configmaps(),
    Namespace("team-a"),
    "settings",
    MergePatch,
    "{\"metadata\":{}}",
  )
  inspect(
    merge.header("content-type").unwrap_or(""),
    content="application/merge-patch+json",
  )
  let json_patch = client.patch_request(
    configmaps(),
    Namespace("team-a"),
    "settings",
    JsonPatch,
    "[]",
  )
  inspect(
    json_patch.header("content-type").unwrap_or(""),
    content="application/json-patch+json",
  )
}
