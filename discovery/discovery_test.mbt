///|
test "decode core resources and their scopes" {
  let body = "{\"groupVersion\":\"v1\",\"resources\":[{\"name\":\"pods\",\"kind\":\"Pod\",\"namespaced\":true,\"verbs\":[\"get\",\"list\",\"watch\"]},{\"name\":\"nodes\",\"kind\":\"Node\",\"namespaced\":false,\"verbs\":[\"get\",\"list\"]}]}"
  let discovered = @discovery.decode_resource_list(body).unwrap()
  inspect(discovered.group(), content="")
  inspect(discovered.version(), content="v1")
  inspect(discovered.resources().length(), content="2")
  let pods = discovered.find("pods").unwrap()
  inspect(pods.kind(), content="Pod")
  inspect(pods.namespaced(), content="true")
  inspect(pods.supports("watch"), content="true")
  let pod_gvr = pods.gvr().unwrap()
  inspect(pod_gvr.group, content="")
  inspect(pod_gvr.version, content="v1")
  inspect(pod_gvr.resource, content="pods")
  inspect(discovered.find("nodes").unwrap().namespaced(), content="false")
}

///|
test "preserve grouped subresources without producing an invalid GVR" {
  let body = "{\"groupVersion\":\"apps/v1\",\"resources\":[{\"name\":\"deployments\",\"kind\":\"Deployment\",\"namespaced\":true,\"verbs\":[\"get\",\"list\",\"watch\"]},{\"name\":\"deployments/status\",\"kind\":\"Deployment\",\"namespaced\":true,\"verbs\":[\"get\",\"patch\",\"update\"]}]}"
  let discovered = @discovery.decode_resource_list(body).unwrap()
  inspect(discovered.group(), content="apps")
  inspect(discovered.version(), content="v1")
  let deployment = discovered.resources()[0]
  inspect(deployment.gvr().unwrap().group, content="apps")
  let status = discovered.resources()[1]
  inspect(status.is_subresource(), content="true")
  inspect(status.gvr() is None, content="true")
  inspect(status.verbs().join(","), content="get,patch,update")
}

///|
test "reject malformed discovery documents with precise context" {
  let cases = [
    ("not-json", "Invalid APIResourceList JSON"),
    ("{\"resources\":[]}", "Missing groupVersion"),
    (
      "{\"groupVersion\":\"apps/v1/extra\",\"resources\":[]}", "Invalid groupVersion: apps/v1/extra",
    ),
    (
      "{\"groupVersion\":\"v1\",\"resources\":[{\"name\":\"pods\",\"kind\":\"Pod\",\"namespaced\":true}]}",
      "resources[0]: missing verbs",
    ),
    (
      "{\"groupVersion\":\"v1\",\"resources\":[{\"name\":\"pods\",\"kind\":\"Pod\",\"namespaced\":\"yes\",\"verbs\":[]}]}",
      "resources[0]: namespaced must be a boolean",
    ),
  ]
  for input_expected in cases {
    let (input, expected) = input_expected
    match @discovery.decode_resource_list(input) {
      Err(message) => inspect(message, content=expected)
      Ok(_) => fail("malformed discovery input must be rejected")
    }
  }
}

///|
test "preserve discovery aliases and categories in server order" {
  let body = "{\"groupVersion\":\"apps/v1\",\"resources\":[{\"name\":\"deployments\",\"singularName\":\"deployment\",\"shortNames\":[\"deploy\",\"dep\"],\"categories\":[\"all\",\"workloads\"],\"kind\":\"Deployment\",\"namespaced\":true,\"verbs\":[\"get\"],\"futureField\":true}]}"
  let deployment = @discovery.decode_resource_list(body).unwrap().resources()[0]
  inspect(deployment.singular_name(), content="deployment")
  inspect(deployment.short_names().join(","), content="deploy,dep")
  inspect(deployment.categories().join(","), content="all,workloads")
}

///|
test "default omitted optional resource metadata to empty values" {
  let body = "{\"groupVersion\":\"v1\",\"resources\":[{\"name\":\"pods\",\"kind\":\"Pod\",\"namespaced\":true,\"verbs\":[\"get\"]}]}"
  let pod = @discovery.decode_resource_list(body).unwrap().resources()[0]
  inspect(pod.singular_name(), content="")
  inspect(pod.short_names().length(), content="0")
  inspect(pod.categories().length(), content="0")
}

///|
test "reject malformed optional resource metadata with index context" {
  let cases = [
    (
      "{\"groupVersion\":\"v1\",\"resources\":[{\"name\":\"pods\",\"kind\":\"Pod\",\"namespaced\":true,\"verbs\":[],\"shortNames\":\"po\"}]}",
      "resources[0]: shortNames must be an array",
    ),
    (
      "{\"groupVersion\":\"v1\",\"resources\":[{\"name\":\"pods\",\"kind\":\"Pod\",\"namespaced\":true,\"verbs\":[],\"categories\":[1]}]}",
      "resources[0]: categories[0] must be a string",
    ),
    (
      "{\"groupVersion\":\"v1\",\"resources\":[{\"name\":\"pods\",\"kind\":\"Pod\",\"namespaced\":true,\"verbs\":[],\"singularName\":false}]}",
      "resources[0]: singularName must be a string",
    ),
  ]
  for input_expected in cases {
    let (input, expected) = input_expected
    match @discovery.decode_resource_list(input) {
      Err(message) => inspect(message, content=expected)
      Ok(_) => fail("malformed optional metadata must be rejected")
    }
  }
}
