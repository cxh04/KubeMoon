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

///|
async test "read a watch response incrementally on its own connection" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (idle, _) = server.accept()
      defer idle.close()
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      inspect(
        request.path,
        content="/api/v1/namespaces/demo/configmaps?watch=1&allowWatchBookmarks=true&resourceVersion=12",
      )
      inspect(
        request.headers.get("authorization").unwrap_or(""),
        content="Bearer test-token",
      )
      connection.send_response(200, "OK")
      connection..write("{\"type\":\"BOOK").flush()
      @async.sleep(20)
      connection..write("MARK\",\"object\":{}}\n").end_response()
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
      bearer_token="test-token",
    )
    let executor = @httptransport.HttpTransport::connect(config)
    defer executor.close()
    let dynamic_client = @client.DynamicClient::DynamicClient(config)
    let resource = @resource.GroupVersionResource(
      group="",
      version="v1",
      resource="configmaps",
    )
    let stream = executor.open_stream(
      dynamic_client.watch_request(
        resource,
        Namespace("demo"),
        resource_version="12",
      ),
    )
    defer stream.close()
    inspect(stream.status(), content="200")
    let body = StringBuilder()
    while stream.read_some(5) is Some(chunk) {
      body.write_string(@utf8.decode(chunk))
    }
    inspect(body.to_string(), content="{\"type\":\"BOOKMARK\",\"object\":{}}\n")
  }
}

///|
async test "reject a streaming request targeting another API server" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let config = @config.ClientConfig(
    server="http://127.0.0.1:\{server.addr.port()}",
  )
  let executor = @httptransport.HttpTransport::connect(config)
  defer executor.close()
  let request = @transport.Request(Get, "http://other-cluster.invalid/api")
  try executor.open_stream(request) catch {
    @httptransport.RequestOriginMismatch(expected~, actual~) => {
      inspect(expected, content=config.server())
      inspect(actual, content="http://other-cluster.invalid/api")
    }
    _ => fail("expected RequestOriginMismatch")
  } noraise {
    _ => fail("a different API server origin must be rejected")
  }
}

///|
async test "stream exposes a 410 response body without treating it as an event" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (idle, _) = server.accept()
      defer idle.close()
      let (connection, _) = server.accept()
      defer connection.close()
      ignore(connection.read_request())
      connection
      ..send_response(410, "Gone")
      ..write("{\"reason\":\"Expired\",\"code\":410}")
      .end_response()
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
    )
    let executor = @httptransport.HttpTransport::connect(config)
    defer executor.close()
    let stream = executor.open_stream(
      Request(Get, "\{config.server()}/api/v1/pods?watch=1"),
    )
    defer stream.close()
    inspect(stream.status(), content="410")
    let body = StringBuilder()
    while stream.read_some(8) is Some(chunk) {
      body.write_string(@utf8.decode(chunk))
    }
    inspect(body.to_string(), content="{\"reason\":\"Expired\",\"code\":410}")
  }
}

///|
async test "streaming API only accepts GET without a body" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let config = @config.ClientConfig(
    server="http://127.0.0.1:\{server.addr.port()}",
  )
  let executor = @httptransport.HttpTransport::connect(config)
  defer executor.close()
  let request = @transport.Request(
    Post,
    "\{config.server()}/api/v1/pods",
    body="{}",
  )
  try executor.open_stream(request) catch {
    @httptransport.StreamingRequiresGet => ()
    _ => fail("expected StreamingRequiresGet")
  } noraise {
    _ => fail("POST must not open a response stream")
  }
}
