///|
/// One resource advertised by a Kubernetes APIResourceList.
pub struct ApiResource {
  group_value : String
  version_value : String
  name_value : String
  singular_name_value : String
  kind_value : String
  namespaced_value : Bool
  verbs_value : Array[String]
  short_names_value : Array[String]
  categories_value : Array[String]
}

///|
pub fn ApiResource::name(self : ApiResource) -> String {
  self.name_value
}

///|
pub fn ApiResource::singular_name(self : ApiResource) -> String {
  self.singular_name_value
}

///|
pub fn ApiResource::kind(self : ApiResource) -> String {
  self.kind_value
}

///|
pub fn ApiResource::namespaced(self : ApiResource) -> Bool {
  self.namespaced_value
}

///|
pub fn ApiResource::verbs(self : ApiResource) -> ArrayView[String] {
  self.verbs_value[:]
}

///|
pub fn ApiResource::short_names(self : ApiResource) -> ArrayView[String] {
  self.short_names_value[:]
}

///|
pub fn ApiResource::categories(self : ApiResource) -> ArrayView[String] {
  self.categories_value[:]
}

///|
pub fn ApiResource::supports(self : ApiResource, verb : String) -> Bool {
  for supported in self.verbs_value {
    if supported == verb {
      return true
    }
  }
  false
}

///|
pub fn ApiResource::is_subresource(self : ApiResource) -> Bool {
  self.name_value.contains("/")
}

///|
/// Return a dynamic resource identifier only for top-level resources.
/// Kubernetes subresources require an object name before their suffix and
/// therefore cannot use the ordinary collection path builder.
pub fn ApiResource::gvr(self : ApiResource) -> @resource.GroupVersionResource? {
  if self.is_subresource() {
    None
  } else {
    Some(
      GroupVersionResource(
        group=self.group_value,
        version=self.version_value,
        resource=self.name_value,
      ),
    )
  }
}

///|
/// Resources served by one Kubernetes group and version.
pub struct ResourceList {
  group_value : String
  version_value : String
  resources_value : Array[ApiResource]
}

///|
pub fn ResourceList::group(self : ResourceList) -> String {
  self.group_value
}

///|
pub fn ResourceList::version(self : ResourceList) -> String {
  self.version_value
}

///|
pub fn ResourceList::resources(self : ResourceList) -> ArrayView[ApiResource] {
  self.resources_value[:]
}

///|
pub fn ResourceList::find(self : ResourceList, name : String) -> ApiResource? {
  for resource in self.resources_value {
    if resource.name() == name {
      return Some(resource)
    }
  }
  None
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
) -> Result[String, String] {
  match fields.get(key) {
    None => Err("missing \{key}")
    Some(String(value)) => Ok(value)
    Some(_) => Err("\{key} must be a string")
  }
}

///|
fn parse_group_version(value : String) -> Result[(String, String), String] {
  let parts = value.split("/").map(fn(part) { part.to_owned() }).to_array()
  match parts {
    [version] if !version.is_empty() => Ok(("", version))
    [group, version] if !group.is_empty() && !version.is_empty() =>
      Ok((group, version))
    _ => Err("Invalid groupVersion: \{value}")
  }
}

///|
fn decode_verbs(fields : Map[String, Json]) -> Result[Array[String], String] {
  guard fields.get("verbs") is Some(value) else { return Err("missing verbs") }
  guard value is Array(values) else { return Err("verbs must be an array") }
  let verbs : Array[String] = []
  for index, item in values {
    match item {
      String(verb) => verbs.push(verb)
      _ => return Err("verbs[\{index}] must be a string")
    }
  }
  Ok(verbs)
}

///|
fn optional_string(
  fields : Map[String, Json],
  key : String,
) -> Result[String, String] {
  match fields.get(key) {
    None => Ok("")
    Some(String(value)) => Ok(value)
    Some(_) => Err("\{key} must be a string")
  }
}

///|
fn optional_string_array(
  fields : Map[String, Json],
  key : String,
) -> Result[Array[String], String] {
  guard fields.get(key) is Some(value) else { return Ok([]) }
  guard value is Array(values) else { return Err("\{key} must be an array") }
  let result : Array[String] = []
  for index, item in values {
    match item {
      String(value) => result.push(value)
      _ => return Err("\{key}[\{index}] must be a string")
    }
  }
  Ok(result)
}

///|
fn decode_resource(
  value : Json,
  group : String,
  version : String,
) -> Result[ApiResource, String] {
  guard value is Object(fields) else {
    return Err("resource must be an object")
  }
  let name = match required_string(fields, "name") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let kind = match required_string(fields, "kind") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let namespaced = match fields.get("namespaced") {
    None => return Err("missing namespaced")
    Some(True) => true
    Some(False) => false
    Some(_) => return Err("namespaced must be a boolean")
  }
  let verbs = match decode_verbs(fields) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let singular_name = match optional_string(fields, "singularName") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let short_names = match optional_string_array(fields, "shortNames") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let categories = match optional_string_array(fields, "categories") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  Ok({
    group_value: group,
    version_value: version,
    name_value: name,
    singular_name_value: singular_name,
    kind_value: kind,
    namespaced_value: namespaced,
    verbs_value: verbs,
    short_names_value: short_names,
    categories_value: categories,
  })
}

///|
/// Decode one `/api/<version>` or `/apis/<group>/<version>` discovery
/// response. Unknown fields are intentionally ignored for forward
/// compatibility.
pub fn decode_resource_list(body : String) -> Result[ResourceList, String] {
  let parsed = @json.parse(body) catch {
    _ => return Err("Invalid APIResourceList JSON")
  }
  guard parsed is Object(fields) else {
    return Err("APIResourceList must be a JSON object")
  }
  let group_version = match required_string(fields, "groupVersion") {
    Ok(value) => value
    Err("missing groupVersion") => return Err("Missing groupVersion")
    Err(message) => return Err(message)
  }
  let (group, version) = match parse_group_version(group_version) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  guard fields.get("resources") is Some(resource_value) else {
    return Err("Missing resources")
  }
  guard resource_value is Array(values) else {
    return Err("resources must be an array")
  }
  let resources : Array[ApiResource] = []
  for index, value in values {
    match decode_resource(value, group, version) {
      Ok(resource) => resources.push(resource)
      Err(message) => return Err("resources[\{index}]: \{message}")
    }
  }
  Ok({ group_value: group, version_value: version, resources_value: resources })
}
