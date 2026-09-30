///|
pub let finalizer_key : String = "cxh04.github.io/kubemoon-cleanup"

///|
pub let owner_annotation : String = "cxh04.github.io/kubemoon-owner-uid"

///|
pub let hash_annotation : String = "cxh04.github.io/kubemoon-content-sha256"

///|
fn content_field(
  source : @object.DynamicObject,
  key : String,
) -> Result[Map[String, Json], String] {
  guard source.raw() is Object(root) else {
    return Err("ConfigMap must be an object")
  }
  match root.get(key) {
    None | Some(Null) => Ok(Map([]))
    Some(Object(values)) => {
      for name, value in values {
        if !(value is String(_)) {
          return Err("ConfigMap \{key}.\{name} must be a string")
        }
      }
      Ok(values)
    }
    _ => Err("ConfigMap \{key} must be an object")
  }
}

///|
fn write_sorted_content(
  builder : StringBuilder,
  field : String,
  values : Map[String, Json],
) -> Unit {
  let keys : Array[String] = []
  for key in values.keys() {
    keys.push(key)
  }
  keys.sort()
  for key in keys {
    guard values.get(key) is Some(String(value)) else { continue }
    builder <+
      "\{field.length()}:\{field}\{key.length()}:\{key}\{value.length()}:\{value}"
  }
}

///|
/// Hash only user data, in sorted key order. Object metadata and JSON field
/// order must not cause target rewrites.
pub fn content_hash(source : @object.DynamicObject) -> Result[String, String] {
  let data = match content_field(source, "data") {
    Ok(data) => data
    Err(message) => return Err(message)
  }
  let binary_data = match content_field(source, "binaryData") {
    Ok(data) => data
    Err(message) => return Err(message)
  }
  let canonical = StringBuilder()
  write_sorted_content(canonical, "data", data)
  write_sorted_content(canonical, "binaryData", binary_data)
  let digest = @crypto.sha256(@utf8.encode(canonical.to_string()))
  let hex = StringBuilder()
  for byte in digest {
    hex <+ "\{byte.to_hex()}"
  }
  Ok(hex.to_string())
}

///|
pub fn desired_configmap(
  mirror : @object.DynamicObject,
  source : @object.DynamicObject,
  target_namespace : String,
) -> Result[Json, String] {
  if mirror.uid().is_empty() {
    return Err("ConfigMirror metadata.uid is required")
  }
  let data = match content_field(source, "data") {
    Ok(data) => data
    Err(message) => return Err(message)
  }
  let binary_data = match content_field(source, "binaryData") {
    Ok(data) => data
    Err(message) => return Err(message)
  }
  let hash = match content_hash(source) {
    Ok(hash) => hash
    Err(message) => return Err(message)
  }
  let annotations : Map[String, Json] = Map([])
  annotations[owner_annotation] = Json::string(mirror.uid())
  annotations[hash_annotation] = Json::string(hash)
  Ok(
    Json::object({
      "apiVersion": Json::string("v1"),
      "kind": Json::string("ConfigMap"),
      "metadata": Json::object({
        "name": Json::string(source.name()),
        "namespace": Json::string(target_namespace),
        "annotations": Json::object(annotations),
      }),
      "data": Json::object(data),
      "binaryData": Json::object(binary_data),
    }),
  )
}
