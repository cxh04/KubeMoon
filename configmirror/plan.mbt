///|
pub(all) enum TargetAction {
  Create(Json)
  Replace(Json)
  Unchanged
  Conflict
} derive(Debug)

///|
pub extend TargetAction with @moonbitlang/core/debug.Debug::{to_repr}

///|
fn annotation(object : @object.DynamicObject, key : String) -> String? {
  guard object.raw() is Object(root) &&
    root.get("metadata") is Some(Object(metadata)) &&
    metadata.get("annotations") is Some(Object(annotations)) else {
    return None
  }
  match annotations.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
pub fn owned_by(
  object : @object.DynamicObject,
  mirror : @object.DynamicObject,
) -> Bool {
  annotation(object, owner_annotation) == Some(mirror.uid()) &&
  !mirror.uid().is_empty()
}

///|
fn replace_body(
  existing : @object.DynamicObject,
  desired : Json,
) -> Result[Json, String] {
  guard existing.raw() is Object(original) &&
    original.get("metadata") is Some(Object(original_metadata)) &&
    desired is Object(wanted) &&
    wanted.get("metadata") is Some(Object(wanted_metadata)) else {
    return Err("Malformed target ConfigMap")
  }
  let body = original.copy()
  let metadata = original_metadata.copy()
  let annotations = match original_metadata.get("annotations") {
    Some(Object(values)) => values.copy()
    _ => Map([])
  }
  guard wanted_metadata.get("annotations") is Some(Object(new_annotations)) else {
    return Err("Missing desired annotations")
  }
  for key, value in new_annotations {
    annotations[key] = value
  }
  metadata["annotations"] = Json::object(annotations)
  metadata["resourceVersion"] = Json::string(existing.resource_version())
  body["metadata"] = Json::object(metadata)
  body["data"] = wanted.get("data").unwrap_or(Json::object(Map([])))
  body["binaryData"] = wanted.get("binaryData").unwrap_or(Json::object(Map([])))
  Ok(Json::object(body))
}

///|
/// Never take over an unrelated ConfigMap. For owned targets, preserve
/// unrelated metadata and use resourceVersion to guard a full replacement.
pub fn plan_target(
  mirror : @object.DynamicObject,
  source : @object.DynamicObject,
  target_namespace : String,
  existing : @object.DynamicObject?,
) -> Result[TargetAction, String] {
  let desired = match desired_configmap(mirror, source, target_namespace) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  guard existing is Some(current) else { return Ok(Create(desired)) }
  if current.name() != source.name() ||
    current.namespace_name() != Some(target_namespace) {
    return Err("Target ConfigMap identity does not match request")
  }
  if !owned_by(current, mirror) {
    return Ok(Conflict)
  }
  if current.resource_version().is_empty() {
    return Err("Target ConfigMap lacks metadata.resourceVersion")
  }
  let source_hash = match content_hash(source) {
    Ok(hash) => hash
    Err(message) => return Err(message)
  }
  let current_hash = match content_hash(current) {
    Ok(hash) => hash
    Err(message) => return Err(message)
  }
  if current_hash == source_hash &&
    annotation(current, hash_annotation) == Some(source_hash) {
    return Ok(Unchanged)
  }
  match replace_body(current, desired) {
    Ok(body) => Ok(Replace(body))
    Err(message) => Err(message)
  }
}
