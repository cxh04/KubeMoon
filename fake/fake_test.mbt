///|
test "serve scripted responses in order and capture requests" {
  let fake = @fake.ScriptedTransport::ScriptedTransport([
    Response(status=200, body="{\"items\":[]}"),
    Response(status=410, body="{\"reason\":\"Expired\"}"),
  ])
  let list = @transport.Request(Get, "/api/v1/configmaps")
  let watch = @transport.Request(Get, "/api/v1/configmaps?watch=true")
  inspect(fake.send(list).unwrap().status(), content="200")
  inspect(fake.send(watch).unwrap().status(), content="410")
  inspect(fake.request_count(), content="2")
  inspect(
    fake.request_at(1).unwrap().path(),
    content="/api/v1/configmaps?watch=true",
  )
}

///|
test "report exhaustion instead of inventing a response" {
  let fake = @fake.ScriptedTransport::ScriptedTransport([])
  match fake.send(Request(Get, "/api")) {
    Err(message) => inspect(message, content="Fake transport script exhausted")
    Ok(_) => fail("an empty script must fail")
  }
}
