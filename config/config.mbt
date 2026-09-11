///|
pub struct ClientConfig {
  server : String
  bearer_token : String?
  ca_file : String?
}

///|
pub fn ClientConfig::ClientConfig(
  server~ : String,
  bearer_token? : String,
  ca_file? : String,
) -> ClientConfig {
  { server: server.trim_end(chars="/").to_owned(), bearer_token, ca_file, }
}

///|
pub fn ClientConfig::server(self : ClientConfig) -> String {
  self.server
}

///|
pub fn ClientConfig::ca_file(self : ClientConfig) -> String? {
  self.ca_file
}

///|
pub fn ClientConfig::authorization_header(self : ClientConfig) -> String? {
  match self.bearer_token {
    Some(token) => Some("Bearer \{token}")
    None => None
  }
}

///|
/// Build the standard Kubernetes in-cluster configuration from the values
/// exposed to a Pod and the mounted ServiceAccount token contents.
///
/// Reading environment variables and files stays at the executable boundary;
/// keeping this constructor pure makes missing credentials deterministic to
/// test and prevents accidental fallback to anonymous access.
pub fn ClientConfig::try_in_cluster(
  host~ : String,
  port~ : String,
  service_account_token~ : String,
) -> Result[ClientConfig, String] {
  if host.is_empty() {
    return Err("Missing KUBERNETES_SERVICE_HOST")
  }
  if port.is_empty() {
    return Err("Missing KUBERNETES_SERVICE_PORT")
  }
  let token = service_account_token.trim().to_owned()
  if token.is_empty() {
    return Err("ServiceAccount token is empty")
  }
  let api_host = if host.contains(":") { "[\{host}]" } else { host }
  Ok(
    ClientConfig(
      server="https://\{api_host}:\{port}",
      bearer_token=token,
      ca_file="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
    ),
  )
}
