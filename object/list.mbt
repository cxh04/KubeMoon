///|
/// A complete Kubernetes collection snapshot. Its resource version belongs to
/// the list response, not to whichever object happens to be last in `items`.
pub struct ListSnapshot {
  version : String
  objects : Array[DynamicObject]
}

///|
pub fn ListSnapshot::resource_version(self : ListSnapshot) -> String {
  self.version
}

///|
pub fn ListSnapshot::items(self : ListSnapshot) -> ArrayView[DynamicObject] {
  self.objects[:]
}

///|
pub fn decode_list_snapshot(body : String) -> Result[ListSnapshot, String] {
  let raw = @json.parse(body) catch {
    _ => return Err("Invalid Kubernetes list JSON")
  }
  guard raw is Object(fields) else {
    return Err("Kubernetes list must be an object")
  }
  guard fields.get("metadata") is Some(Object(metadata)) else {
    return Err("Missing list metadata")
  }
  guard metadata.get("resourceVersion") is Some(String(version)) &&
    !version.is_empty() else {
    return Err("Missing list metadata.resourceVersion")
  }
  guard fields.get("items") is Some(Array(items)) else {
    return Err("Missing list items array")
  }
  let objects : Array[DynamicObject] = []
  for index, item in items {
    match DynamicObject::try_from_json(item) {
      Ok(object) => objects.push(object)
      Err(message) => return Err("items[\{index}]: \{message}")
    }
  }
  Ok({ version, objects, })
}
