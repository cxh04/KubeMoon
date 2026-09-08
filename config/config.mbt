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
