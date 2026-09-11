///|
pub(all) struct GroupVersionResource {
  group : String
  version : String
  resource : String
} derive(Debug, Eq)

///|
pub fn GroupVersionResource::GroupVersionResource(
  group~ : String,
  version~ : String,
  resource~ : String,
) -> GroupVersionResource {
  { group, version, resource, }
}

///|
pub(all) enum Scope {
  Cluster
  Namespace(String)
} derive(Debug, Eq)

///|
fn GroupVersionResource::api_prefix(self : GroupVersionResource) -> String {
  if self.group.is_empty() {
    "/api/\{self.version}"
  } else {
    "/apis/\{self.group}/\{self.version}"
  }
}

///|
pub fn collection_path(
  resource : GroupVersionResource,
  scope : Scope,
) -> String {
  let prefix = resource.api_prefix()
  match scope {
    Cluster => "\{prefix}/\{resource.resource}"
    Namespace(namespace_name) =>
      "\{prefix}/namespaces/\{namespace_name}/\{resource.resource}"
  }
}

///|
pub fn object_path(
  resource : GroupVersionResource,
  scope : Scope,
  name : String,
) -> String {
  "\{collection_path(resource, scope)}/\{name}"
}
