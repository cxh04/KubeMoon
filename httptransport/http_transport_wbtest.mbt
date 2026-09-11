///|
test "select system roots or an explicit Kubernetes PEM CA" {
  match trust_root(None) {
    SystemRoot => ()
    _ => fail("system roots should be the default")
  }
  match
    trust_root(Some("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")) {
    CustomPemFile(path) =>
      inspect(
        path,
        content="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
      )
    _ => fail("an explicit CA file must become the exclusive trust root")
  }
}

///|
test "map every Kubernetes request method to async HTTP" {
  inspect(@debug.to_string(http_method(Get)), content="Get")
  inspect(@debug.to_string(http_method(Post)), content="Post")
  inspect(@debug.to_string(http_method(Put)), content="Put")
  inspect(@debug.to_string(http_method(Patch)), content="Patch")
  inspect(@debug.to_string(http_method(Delete)), content="Delete")
}
