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

///|
test "build in-cluster credentials from service account inputs" {
  let config = @config.ClientConfig::try_in_cluster(
    host="10.96.0.1",
    port="443",
    service_account_token="  pod-token\n",
  ).unwrap()
  inspect(config.server(), content="https://10.96.0.1:443")
  inspect(
    config.authorization_header().unwrap_or(""),
    content="Bearer pod-token",
  )
  inspect(
    config.ca_file().unwrap_or(""),
    content="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
  )
}

///|
test "reject incomplete in-cluster discovery inputs" {
  match
    @config.ClientConfig::try_in_cluster(
      host="",
      port="443",
      service_account_token="token",
    ) {
    Err(message) => inspect(message, content="Missing KUBERNETES_SERVICE_HOST")
    Ok(_) => fail("an empty API host must be rejected")
  }
  match
    @config.ClientConfig::try_in_cluster(
      host="10.96.0.1",
      port="443",
      service_account_token=" \n ",
    ) {
    Err(message) => inspect(message, content="ServiceAccount token is empty")
    Ok(_) => fail("a blank token must be rejected")
  }
}
