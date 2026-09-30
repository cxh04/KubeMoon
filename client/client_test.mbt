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

///|
test "build core and grouped API resource list requests" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example", bearer_token="secret"),
  )
  let core = client.resource_list_request(group="", version="v1").unwrap()
  inspect(core.verb().http_name(), content="GET")
  inspect(core.path(), content="https://cluster.example/api/v1")
  inspect(core.header("authorization").unwrap_or(""), content="Bearer secret")
  let apps = client.resource_list_request(group="apps", version="v1").unwrap()
  inspect(apps.path(), content="https://cluster.example/apis/apps/v1")
}

///|
test "reject malformed API resource list request coordinates" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example"),
  )
  let cases = [
    (("apps", ""), "Discovery version must not be empty"),
    (("apps/v1", "v1"), "Discovery group must not contain '/'"),
    (("apps", "v1/status"), "Discovery version must not contain '/'"),
  ]
  for coordinates_expected in cases {
    let ((group, version), expected) = coordinates_expected
    match client.resource_list_request(group~, version~) {
      Err(message) => inspect(message, content=expected)
      Ok(_) => fail("malformed discovery coordinates must be rejected")
    }
  }
}

///|
test "build the core API versions discovery request" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example/", bearer_token="secret"),
  )
  let request = client.api_versions_request()
  inspect(request.verb().http_name(), content="GET")
  inspect(request.path(), content="https://cluster.example/api")
  inspect(request.header("accept").unwrap_or(""), content="application/json")
  inspect(
    request.header("authorization").unwrap_or(""),
    content="Bearer secret",
  )
  inspect(request.body() is None, content="true")
}

///|
test "build the named API groups discovery request" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example"),
  )
  let request = client.api_groups_request()
  inspect(request.verb().http_name(), content="GET")
  inspect(request.path(), content="https://cluster.example/apis")
  inspect(request.header("accept").unwrap_or(""), content="application/json")
  inspect(request.header("authorization") is None, content="true")
}

///|
test "build watch requests with an opaque encoded resource version" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example", bearer_token="secret"),
  )
  let request = client.watch_request(
    configmaps(),
    Namespace("team-a"),
    resource_version="42/+中文",
  )
  inspect(request.verb().http_name(), content="GET")
  inspect(
    request.path(),
    content="https://cluster.example/api/v1/namespaces/team-a/configmaps?watch=1&allowWatchBookmarks=true&resourceVersion=42%2F%2B%E4%B8%AD%E6%96%87",
  )
  inspect(
    request.header("authorization").unwrap_or(""),
    content="Bearer secret",
  )
  inspect(request.body() is None, content="true")
}

///|
test "watch requests can start at the server's current version" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example"),
  )
  let request = client.watch_request(
    GroupVersionResource(group="apps", version="v1", resource="deployments"),
    Cluster,
  )
  inspect(
    request.path(),
    content="https://cluster.example/apis/apps/v1/deployments?watch=1&allowWatchBookmarks=true",
  )
}

///|
test "status patch targets the CRD subresource" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example"),
  )
  let request = client.patch_status_request(
    GroupVersionResource(
      group="kubemoon.cxh04.github.io",
      version="v1alpha1",
      resource="configmirrors",
    ),
    Namespace("demo"),
    "mirror",
    "{\"status\":{\"phase\":\"Ready\"}}",
  )
  assert_eq(
    request.path(),
    "https://cluster.example/apis/kubemoon.cxh04.github.io/v1alpha1/namespaces/demo/configmirrors/mirror/status",
  )
  assert_eq(request.verb().http_name(), "PATCH")
  assert_eq(
    request.header("content-type"),
    Some("application/merge-patch+json"),
  )
}

///|
test "list continuation encodes the token without changing the resource path" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example"),
  )
  let request = client.list_page_request(
    configmaps(),
    Namespace("demo"),
    "next/+",
  )
  assert_eq(
    request.path(),
    "https://cluster.example/api/v1/namespaces/demo/configmaps?continue=next%2F%2B",
  )
}

///|
test "UID-preconditioned delete prevents a same-name race" {
  let client = @client.DynamicClient::DynamicClient(
    ClientConfig(server="https://cluster.example"),
  )
  let request = client.delete_with_uid_request(
    configmaps(),
    Namespace("west"),
    "settings",
    "target-uid",
  )
  assert_eq(request.verb().http_name(), "DELETE")
  assert_eq(request.header("content-type"), Some("application/json"))
  assert_eq(
    @json.parse(request.body().unwrap()),
    @json.parse("{\"preconditions\":{\"uid\":\"target-uid\"}}"),
  )
}
