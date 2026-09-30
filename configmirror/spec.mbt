///|
pub struct MirrorSpec {
  source_namespace : String
  source_name : String
  target_namespaces : Array[String]
}

///|
pub fn MirrorSpec::source_namespace(self : MirrorSpec) -> String {
  self.source_namespace
}

///|
pub fn MirrorSpec::source_name(self : MirrorSpec) -> String {
  self.source_name
}

///|
pub fn MirrorSpec::targets(self : MirrorSpec) -> ArrayView[String] {
  self.target_namespaces[:]
}

///|
fn required_string(fields : Map[String, Json], field : String) -> String? {
  match fields.get(field) {
    Some(String(value)) if !value.is_empty() => Some(value)
    _ => None
  }
}

///|
/// Parse the intentionally small v1alpha1 contract; reject ambiguous target
/// lists before the controller begins making cross-namespace writes.
pub fn decode_spec(
  object : @object.DynamicObject,
) -> Result[MirrorSpec, String] {
  guard object.raw() is Object(root) && root.get("spec") is Some(Object(spec)) else {
    return Err("Missing ConfigMirror spec")
  }
  guard spec.get("source") is Some(Object(source)) else {
    return Err("Missing spec.source")
  }
  guard required_string(source, "namespace") is Some(source_namespace) &&
    required_string(source, "name") is Some(source_name) else {
    return Err("spec.source requires namespace and name")
  }
  guard spec.get("targets") is Some(Array(targets)) else {
    return Err("spec.targets must be an array")
  }
  if targets.is_empty() {
    return Err("spec.targets must not be empty")
  }
  let seen : Map[String, Bool] = Map([])
  let target_namespaces : Array[String] = []
  for index, target in targets {
    guard target is String(namespace_name) && !namespace_name.is_empty() else {
      return Err("spec.targets[\{index}] must be a non-empty namespace")
    }
    if namespace_name == source_namespace {
      return Err("spec.targets[\{index}] names the source namespace")
    }
    if seen.contains(namespace_name) {
      return Err("spec.targets[\{index}] duplicates \{namespace_name}")
    }
    seen[namespace_name] = true
    target_namespaces.push(namespace_name)
  }
  Ok({ source_namespace, source_name, target_namespaces, })
}
