///|
test "request keeps method path headers and body together" {
  let request = @transport.Request(
    Patch,
    "/api/v1/namespaces/default/configmaps/settings",
    body="{\"metadata\":{}}",
  ).with_header("Content-Type", "application/merge-patch+json")
  assert_eq(request.verb().http_name(), "PATCH")
  assert_eq(
    request.header("content-type"),
    Some("application/merge-patch+json"),
  )
  assert_eq(request.body(), Some("{\"metadata\":{}}"))
}

///|
test "response distinguishes successful and failed status codes" {
  let ok = @transport.Response(status=200, body="{}")
  let missing = @transport.Response(status=404, body="not found")
  assert_true(ok.is_success())
  assert_false(missing.is_success())
  assert_eq(missing.body(), "not found")
}
