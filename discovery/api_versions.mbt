///|
/// Core API versions advertised by the Kubernetes `/api` endpoint.
pub struct ApiVersions {
  versions_value : Array[String]
}

///|
pub fn ApiVersions::versions(self : ApiVersions) -> ArrayView[String] {
  self.versions_value[:]
}

///|
pub fn ApiVersions::supports(self : ApiVersions, version : String) -> Bool {
  for supported in self.versions_value {
    if supported == version {
      return true
    }
  }
  false
}

///|
/// Decode the core API version directory returned by Kubernetes `/api`.
/// Unknown fields are ignored and the server's version order is preserved.
pub fn decode_api_versions(body : String) -> Result[ApiVersions, String] {
  let parsed = @json.parse(body) catch {
    _ => return Err("Invalid APIVersions JSON")
  }
  guard parsed is Object(fields) else {
    return Err("APIVersions must be a JSON object")
  }
  guard fields.get("versions") is Some(value) else {
    return Err("Missing versions")
  }
  guard value is Array(values) else { return Err("versions must be an array") }
  let versions : Array[String] = []
  for index, item in values {
    match item {
      String(version) => versions.push(version)
      _ => return Err("versions[\{index}] must be a string")
    }
  }
  Ok({ versions_value: versions, })
}
