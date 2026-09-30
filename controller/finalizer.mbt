///|
fn metadata_of(object : @object.DynamicObject) -> Map[String, Json]? {
  match object.raw() {
    Object(fields) =>
      match fields.get("metadata") {
        Some(Object(metadata)) => Some(metadata)
        _ => None
      }
    _ => None
  }
}

///|
pub fn is_deleting(object : @object.DynamicObject) -> Bool {
  guard metadata_of(object) is Some(metadata) else { return false }
  match metadata.get("deletionTimestamp") {
    Some(String(value)) => !value.is_empty()
    _ => false
  }
}

///|
fn finalizers_of(metadata : Map[String, Json]) -> Result[Array[String], String] {
  match metadata.get("finalizers") {
    None | Some(Null) => Ok([])
    Some(Array(values)) => {
      let names : Array[String] = []
      for value in values {
        match value {
          String(name) => names.push(name)
          _ => return Err("metadata.finalizers must contain strings")
        }
      }
      Ok(names)
    }
    _ => Err("metadata.finalizers must be an array")
  }
}

///|
/// Produce a merge patch guarded by metadata.resourceVersion. `None` means
/// that the desired finalizer state is already present and no API call is due.
/// The caller must retry a 409 against a freshly read object.
pub fn finalizer_patch(
  object : @object.DynamicObject,
  key : String,
  remove~ : Bool,
) -> Result[String?, String] {
  if !key.contains("/") || key.has_prefix("/") || key.has_suffix("/") {
    return Err("Finalizer key must have a qualified prefix")
  }
  if object.resource_version().is_empty() {
    return Err("Finalizer patch requires metadata.resourceVersion")
  }
  guard metadata_of(object) is Some(metadata) else {
    return Err("Missing metadata")
  }
  let finalizers = match finalizers_of(metadata) {
    Ok(names) => names
    Err(message) => return Err(message)
  }
  let already_present = finalizers.contains(key)
  if (remove && !already_present) || (!remove && already_present) {
    return Ok(None)
  }
  if !remove && is_deleting(object) {
    return Err("Cannot add a finalizer after deletion has started")
  }
  let next : Array[Json] = []
  for name in finalizers {
    if name != key {
      next.push(Json::string(name))
    }
  }
  if !remove {
    next.push(Json::string(key))
  }
  let patch = Json::object({
    "metadata": Json::object({
      "resourceVersion": Json::string(object.resource_version()),
      "finalizers": Json::array(next),
    }),
  })
  Ok(Some(patch.stringify()))
}
