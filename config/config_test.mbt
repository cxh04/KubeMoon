///|
test "explicit config normalizes the API server" {
  let config = @config.ClientConfig(
    server="https://127.0.0.1:6443///",
    bearer_token="demo-token",
    ca_file="cluster-ca.crt",
  )
  assert_eq(config.server(), "https://127.0.0.1:6443")
  assert_eq(config.ca_file(), Some("cluster-ca.crt"))
}

///|
test "authorization header is derived without exposing the token field" {
  let authenticated = @config.ClientConfig(
    server="https://cluster.example",
    bearer_token="demo-token",
  )
  let anonymous = @config.ClientConfig(server="http://127.0.0.1:8001")
  assert_eq(authenticated.authorization_header(), Some("Bearer demo-token"))
  assert_eq(anonymous.authorization_header(), None)
}
