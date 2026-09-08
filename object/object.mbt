///|
/// An unstructured Kubernetes object with its scheduling identity extracted.
///
/// The original JSON is retained so clients and controllers do not discard
/// fields they do not understand.
pub struct DynamicObject {
  raw : Json
  name : String
  namespace_name : String?
  uid_value : String
  version : String
}

///|
fn json_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn metadata_fields(raw : Json) -> Map[String, Json]? {
  match raw {
    Object(fields) =>
      match fields.get("metadata") {
        Some(Object(metadata)) => Some(metadata)
        _ => None
      }
    _ => None
  }
}

///|
/// Decode the metadata needed by the runtime without imposing a schema on the
/// rest of the Kubernetes object.
pub fn DynamicObject::try_from_json(
  raw : Json,
) -> Result[DynamicObject, String] {
  guard metadata_fields(raw) is Some(metadata) else {
    return Err("Missing metadata")
  }
  guard json_string(metadata, "name") is Some(name) else {
    return Err("Missing metadata.name")
  }
  Ok({
    raw,
    name,
    namespace_name: json_string(metadata, "namespace"),
    uid_value: json_string(metadata, "uid").unwrap_or(""),
    version: json_string(metadata, "resourceVersion").unwrap_or(""),
  })
}

///|
/// Decode a dynamic object, aborting when required Kubernetes identity is
/// absent. Prefer `try_from_json` at network boundaries.
pub fn DynamicObject::from_json(raw : Json) -> DynamicObject {
  match DynamicObject::try_from_json(raw) {
    Ok(object) => object
    Err(message) => abort(message)
  }
}

///|
pub fn DynamicObject::raw(self : DynamicObject) -> Json {
  self.raw
}

///|
pub fn DynamicObject::name(self : DynamicObject) -> String {
  self.name
}

///|
pub fn DynamicObject::namespace_name(self : DynamicObject) -> String? {
  self.namespace_name
}

///|
pub fn DynamicObject::uid(self : DynamicObject) -> String {
  self.uid_value
}

///|
pub fn DynamicObject::resource_version(self : DynamicObject) -> String {
  self.version
}

///|
/// Stable queue/store key: `namespace/name` for namespaced resources and just
/// `name` for cluster-scoped resources.
pub fn DynamicObject::identity(self : DynamicObject) -> String {
  match self.namespace_name {
    Some(namespace_name) => "\{namespace_name}/\{self.name}"
    None => self.name
  }
}
