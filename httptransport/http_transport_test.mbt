///|
async test "execute authenticated GET and POST on one HTTP connection" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (connection, _) = server.accept()
      defer connection.close()

      let discovery = connection.read_request()
      inspect(@debug.to_string(discovery.meth), content="Get")
      inspect(discovery.path, content="/apis")
      inspect(
        discovery.headers.get("authorization").unwrap_or(""),
        content="Bearer test-token",
      )
      connection
      ..send_response(200, "OK")
      ..write("{\"groups\":[]}")
      .end_response()

      let create = connection.read_request()
      inspect(@debug.to_string(create.meth), content="Post")
      inspect(create.path, content="/api/v1/namespaces/demo/configmaps")
      inspect(
        create.headers.get("content-type").unwrap_or(""),
        content="application/json",
      )
      inspect(
        create.headers.get("authorization").unwrap_or(""),
        content="Bearer test-token",
      )
      inspect(
        connection.read_all().text(),
        content="{\"metadata\":{\"name\":\"settings\"}}",
      )
      connection
      ..send_response(201, "Created")
      ..write("{\"metadata\":{\"name\":\"settings\"}}")
      .end_response()
    }

    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
      bearer_token="test-token",
    )
    let dynamic_client = @client.DynamicClient::DynamicClient(config)
    let executor = @httptransport.HttpTransport::connect(config)
    defer executor.close()

    let discovery = executor.send(dynamic_client.api_groups_request())
    inspect(discovery.status(), content="200")
    inspect(discovery.body(), content="{\"groups\":[]}")

    let configmaps = @resource.GroupVersionResource(
      group="",
      version="v1",
      resource="configmaps",
    )
    let create = executor.send(
      dynamic_client.create_request(
        configmaps,
        Namespace("demo"),
        "{\"metadata\":{\"name\":\"settings\"}}",
      ),
    )
    inspect(create.status(), content="201")
    inspect(create.body(), content="{\"metadata\":{\"name\":\"settings\"}}")
  }
}

///|
async test "reject a request targeting another API server" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let config = @config.ClientConfig(
    server="http://127.0.0.1:\{server.addr.port()}",
  )
  let executor = @httptransport.HttpTransport::connect(config)
  defer executor.close()
  let request = @transport.Request(Get, "http://other-cluster.invalid/api")
  try executor.send(request) catch {
    @httptransport.RequestOriginMismatch(expected~, actual~) => {
      inspect(expected, content=config.server())
      inspect(actual, content="http://other-cluster.invalid/api")
    }
    _ => fail("expected RequestOriginMismatch")
  } noraise {
    _ => fail("a different API server origin must be rejected")
  }
}
