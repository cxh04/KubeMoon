///|
/// One group and version pair advertised by Kubernetes discovery.
pub struct GroupVersionForDiscovery {
  group_version_value : String
  version_value : String
}

///|
pub fn GroupVersionForDiscovery::group_version(
  self : GroupVersionForDiscovery,
) -> String {
  self.group_version_value
}

///|
pub fn GroupVersionForDiscovery::version(
  self : GroupVersionForDiscovery,
) -> String {
  self.version_value
}

///|
/// One named Kubernetes API group and its served versions.
pub struct ApiGroup {
  name_value : String
  versions_value : Array[GroupVersionForDiscovery]
  preferred_version_value : GroupVersionForDiscovery?
}

///|
pub fn ApiGroup::name(self : ApiGroup) -> String {
  self.name_value
}

///|
pub fn ApiGroup::versions(
  self : ApiGroup,
) -> ArrayView[GroupVersionForDiscovery] {
  self.versions_value[:]
}

///|
pub fn ApiGroup::preferred_version(
  self : ApiGroup,
) -> GroupVersionForDiscovery? {
  self.preferred_version_value
}

///|
pub fn ApiGroup::find_version(
  self : ApiGroup,
  version : String,
) -> GroupVersionForDiscovery? {
  for candidate in self.versions_value {
    if candidate.version() == version {
      return Some(candidate)
    }
  }
  None
}

///|
/// Named API groups returned by the Kubernetes `/apis` endpoint.
pub struct ApiGroupList {
  groups_value : Array[ApiGroup]
}

///|
pub fn ApiGroupList::groups(self : ApiGroupList) -> ArrayView[ApiGroup] {
  self.groups_value[:]
}

///|
pub fn ApiGroupList::find(self : ApiGroupList, name : String) -> ApiGroup? {
  for group in self.groups_value {
    if group.name() == name {
      return Some(group)
    }
  }
  None
}

///|
fn decode_group_version(
  value : Json,
  group : String,
) -> Result[GroupVersionForDiscovery, String] {
  guard value is Object(fields) else { return Err("version must be an object") }
  let group_version = match required_string(fields, "groupVersion") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let version = match required_string(fields, "version") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let expected = "\{group}/\{version}"
  if group_version != expected {
    return Err("groupVersion must match \{expected}")
  }
  Ok({ group_version_value: group_version, version_value: version })
}

///|
fn contains_group_version(
  versions : Array[GroupVersionForDiscovery],
  expected : GroupVersionForDiscovery,
) -> Bool {
  for candidate in versions {
    if candidate.group_version() == expected.group_version() &&
      candidate.version() == expected.version() {
      return true
    }
  }
  false
}

///|
fn decode_api_group(value : Json, index : Int) -> Result[ApiGroup, String] {
  guard value is Object(fields) else {
    return Err("groups[\{index}]: group must be an object")
  }
  let name = match required_string(fields, "name") {
    Ok(value) => value
    Err(message) => return Err("groups[\{index}]: \{message}")
  }
  guard fields.get("versions") is Some(version_value) else {
    return Err("groups[\{index}]: missing versions")
  }
  guard version_value is Array(values) else {
    return Err("groups[\{index}]: versions must be an array")
  }
  let versions : Array[GroupVersionForDiscovery] = []
  for version_index, version_value in values {
    match decode_group_version(version_value, name) {
      Ok(version) => versions.push(version)
      Err(message) =>
        return Err("groups[\{index}].versions[\{version_index}]: \{message}")
    }
  }
  let preferred_version = match fields.get("preferredVersion") {
    None => None
    Some(value) =>
      match decode_group_version(value, name) {
        Ok(version) => Some(version)
        Err(message) =>
          return Err("groups[\{index}].preferredVersion: \{message}")
      }
  }
  match preferred_version {
    Some(version) if !contains_group_version(versions, version) =>
      return Err(
        "groups[\{index}].preferredVersion: preferred version must appear in versions",
      )
    _ => ()
  }
  Ok({
    name_value: name,
    versions_value: versions,
    preferred_version_value: preferred_version,
  })
}

///|
/// Decode the legacy discovery document returned by Kubernetes `/apis`.
/// Unknown fields are ignored and the server's group and version order is
/// preserved.
pub fn decode_api_group_list(body : String) -> Result[ApiGroupList, String] {
  let parsed = @json.parse(body) catch {
    _ => return Err("Invalid APIGroupList JSON")
  }
  guard parsed is Object(fields) else {
    return Err("APIGroupList must be a JSON object")
  }
  guard fields.get("groups") is Some(group_value) else {
    return Err("Missing groups")
  }
  guard group_value is Array(values) else {
    return Err("groups must be an array")
  }
  let groups : Array[ApiGroup] = []
  for index, value in values {
    match decode_api_group(value, index) {
      Ok(group) => groups.push(group)
      Err(message) => return Err(message)
    }
  }
  Ok({ groups_value: groups })
}
