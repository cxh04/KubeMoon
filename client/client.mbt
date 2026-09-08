///|
pub(all) enum PatchType {
  MergePatch
  JsonPatch
} derive(Debug, Eq)

///|
pub struct DynamicClient {
  config : @config.ClientConfig
}

///|
pub fn DynamicClient::DynamicClient(
  config : @config.ClientConfig,
) -> DynamicClient {
  { config, }
}

///|
fn DynamicClient::endpoint(self : DynamicClient, path : String) -> String {
  "\{self.config.server()}\{path}"
}

///|
fn DynamicClient::prepare(
  self : DynamicClient,
  request : @transport.Request,
) -> @transport.Request {
  let request = request.with_header("Accept", "application/json")
  match self.config.authorization_header() {
    Some(value) => request.with_header("Authorization", value)
    None => request
  }
}

///|
/// Build a request for one Kubernetes APIResourceList.
/// An empty group selects the core API; this method does not enumerate API
/// groups or send the request.
pub fn DynamicClient::resource_list_request(
  self : DynamicClient,
  group~ : String,
  version~ : String,
) -> Result[@transport.Request, String] {
  if version.is_empty() {
    return Err("Discovery version must not be empty")
  }
  if group.contains("/") {
    return Err("Discovery group must not contain '/'")
  }
  if version.contains("/") {
    return Err("Discovery version must not contain '/'")
  }
  let path = if group.is_empty() {
    "/api/\{version}"
  } else {
    "/apis/\{group}/\{version}"
  }
  Ok(self.prepare(Request(Get, self.endpoint(path))))
}

///|
pub fn DynamicClient::list_request(
  self : DynamicClient,
  resource : @resource.GroupVersionResource,
  scope : @resource.Scope,
) -> @transport.Request {
  let path = @resource.collection_path(resource, scope)
  self.prepare(Request(Get, self.endpoint(path)))
}

///|
pub fn DynamicClient::get_request(
  self : DynamicClient,
  resource : @resource.GroupVersionResource,
  scope : @resource.Scope,
  name : String,
) -> @transport.Request {
  let path = @resource.object_path(resource, scope, name)
  self.prepare(Request(Get, self.endpoint(path)))
}

///|
pub fn DynamicClient::create_request(
  self : DynamicClient,
  resource : @resource.GroupVersionResource,
  scope : @resource.Scope,
  body : String,
) -> @transport.Request {
  let path = @resource.collection_path(resource, scope)
  self.prepare(
    @transport.Request(Post, self.endpoint(path), body~).with_header(
      "Content-Type", "application/json",
    ),
  )
}

///|
pub fn DynamicClient::replace_request(
  self : DynamicClient,
  resource : @resource.GroupVersionResource,
  scope : @resource.Scope,
  name : String,
  body : String,
) -> @transport.Request {
  let path = @resource.object_path(resource, scope, name)
  self.prepare(
    @transport.Request(Put, self.endpoint(path), body~).with_header(
      "Content-Type", "application/json",
    ),
  )
}

///|
pub fn DynamicClient::patch_request(
  self : DynamicClient,
  resource : @resource.GroupVersionResource,
  scope : @resource.Scope,
  name : String,
  patch_type : PatchType,
  body : String,
) -> @transport.Request {
  let path = @resource.object_path(resource, scope, name)
  let media_type = match patch_type {
    MergePatch => "application/merge-patch+json"
    JsonPatch => "application/json-patch+json"
  }
  self.prepare(
    @transport.Request(Patch, self.endpoint(path), body~).with_header(
      "Content-Type", media_type,
    ),
  )
}

///|
pub fn DynamicClient::delete_request(
  self : DynamicClient,
  resource : @resource.GroupVersionResource,
  scope : @resource.Scope,
  name : String,
) -> @transport.Request {
  let path = @resource.object_path(resource, scope, name)
  self.prepare(Request(Delete, self.endpoint(path)))
}
