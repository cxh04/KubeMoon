///|
async test "LIST snapshot version starts WATCH and events advance resume point" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (list, _) = server.accept()
      defer list.close()
      let request = list.read_request()
      assert_true(request.path.contains("/api/v1/namespaces/demo/configmaps"))
      list.send_response(200, "OK")
      list.write(
        "{\"metadata\":{\"resourceVersion\":\"42\"},\"items\":[{\"metadata\":{\"name\":\"before\",\"namespace\":\"demo\",\"resourceVersion\":\"41\"}}]}",
      )
      list.end_response()
      let (watch, _) = server.accept()
      defer watch.close()
      let request = watch.read_request()
      assert_true(request.path.contains("watch=1"))
      assert_true(request.path.contains("resourceVersion=42"))
      watch.send_response(200, "OK")
      watch.write(
        "{\"type\":\"BOOKMARK\",\"object\":{\"metadata\":{\"resourceVersion\":\"44\"}}}\n",
      )
      watch.write(
        "{\"type\":\"ADDED\",\"object\":{\"metadata\":{\"name\":\"after\",\"namespace\":\"demo\",\"resourceVersion\":\"45\"}}}\n",
      )
      watch.end_response()
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
    )
    let transport = @httptransport.HttpTransport::connect(config)
    defer transport.close()
    let client = @client.DynamicClient::DynamicClient(config)
    let reflector = @reflector.Reflector::Reflector()
    let resource = @resource.GroupVersionResource(
      group="",
      version="v1",
      resource="configmaps",
    )
    let outcome = @runtime.sync_once(
      transport,
      client,
      resource,
      Namespace("demo"),
      reflector,
      list_first=true,
    ).unwrap()
    assert_true(outcome is Resume)
    assert_eq(reflector.resource_version(), "45")
    assert_eq(reflector.next_key(), Some("demo/before"))
    assert_eq(reflector.next_key(), Some("demo/after"))
  }
}

///|
async test "HTTP 410 requests a relist after a valid snapshot" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (list, _) = server.accept()
      defer list.close()
      ignore(list.read_request())
      list.send_response(200, "OK")
      list.write("{\"metadata\":{\"resourceVersion\":\"8\"},\"items\":[]}")
      list.end_response()
      let (watch, _) = server.accept()
      defer watch.close()
      ignore(watch.read_request())
      watch.send_response(410, "Gone")
      watch.end_response()
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
    )
    let transport = @httptransport.HttpTransport::connect(config)
    defer transport.close()
    let client = @client.DynamicClient::DynamicClient(config)
    let reflector = @reflector.Reflector::Reflector()
    let resource = @resource.GroupVersionResource(
      group="",
      version="v1",
      resource="configmaps",
    )
    let outcome = @runtime.sync_once(
      transport,
      client,
      resource,
      Namespace("demo"),
      reflector,
      list_first=true,
    ).unwrap()
    assert_true(outcome is Relist)
    assert_eq(reflector.resource_version(), "8")
  }
}

///|
async test "paginated LIST completes before the reflector cache is replaced" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (list, _) = server.accept()
      defer list.close()
      ignore(list.read_request())
      list.send_response(200, "OK")
      list.write(
        "{\"metadata\":{\"resourceVersion\":\"42\",\"continue\":\"next/+\"},\"items\":[{\"metadata\":{\"name\":\"first\",\"namespace\":\"demo\",\"resourceVersion\":\"40\"}}]}",
      )
      list.end_response()
      let next = list.read_request()
      assert_true(next.path.contains("continue=next%2F%2B"))
      list.send_response(200, "OK")
      list.write(
        "{\"metadata\":{\"resourceVersion\":\"42\"},\"items\":[{\"metadata\":{\"name\":\"second\",\"namespace\":\"demo\",\"resourceVersion\":\"41\"}}]}",
      )
      list.end_response()
      let (watch, _) = server.accept()
      defer watch.close()
      let request = watch.read_request()
      assert_true(request.path.contains("resourceVersion=42"))
      watch.send_response(200, "OK")
      watch.end_response()
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
    )
    let transport = @httptransport.HttpTransport::connect(config)
    defer transport.close()
    let client = @client.DynamicClient::DynamicClient(config)
    let reflector = @reflector.Reflector::Reflector()
    let resource = @resource.GroupVersionResource(
      group="",
      version="v1",
      resource="configmaps",
    )
    assert_true(
      @runtime.sync_once(
        transport,
        client,
        resource,
        Namespace("demo"),
        reflector,
        list_first=true,
      ).unwrap()
      is Resume,
    )
    assert_eq(reflector.next_key(), Some("demo/first"))
    assert_eq(reflector.next_key(), Some("demo/second"))
  }
}

///|
async fn scripted_session(
  list_status : Int,
  list_body : String,
  watch_status : Int,
  watch_body : String,
) -> Result[@runtime.WatchOutcome, String] {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (list, _) = server.accept()
      defer list.close()
      ignore(list.read_request())
      list.send_response(list_status, "Result")
      list.write(list_body)
      list.end_response()
      if list_status == 200 && list_body.contains("resourceVersion") {
        let (watch, _) = server.accept()
        defer watch.close()
        ignore(watch.read_request())
        watch.send_response(watch_status, "Result")
        watch.write(watch_body)
        watch.end_response()
      }
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
    )
    let transport = @httptransport.HttpTransport::connect(config)
    defer transport.close()
    let client = @client.DynamicClient::DynamicClient(config)
    let reflector = @reflector.Reflector::Reflector()
    @runtime.sync_once(
      transport,
      client,
      GroupVersionResource(group="", version="v1", resource="configmaps"),
      Namespace("demo"),
      reflector,
      list_first=true,
    )
  }
}

///|
async test "LIST status and malformed payloads fail without opening WATCH" {
  let valid = "{\"metadata\":{\"resourceVersion\":\"1\"},\"items\":[]}"
  assert_true(scripted_session(429, "{}", 200, "") is Ok(Retry))
  assert_true(scripted_session(403, "denied", 200, "") is Err(_))
  assert_true(scripted_session(200, "{}", 200, "") is Err(_))
  assert_true(scripted_session(200, valid, 503, "") is Ok(Retry))
  assert_true(scripted_session(200, valid, 403, "") is Err(_))
}

///|
async test "watch error events and truncated events remain distinct" {
  let valid = "{\"metadata\":{\"resourceVersion\":\"1\"},\"items\":[]}"
  let expired = "{\"type\":\"ERROR\",\"object\":{\"reason\":\"Expired\",\"code\":410}}\n"
  assert_true(scripted_session(200, valid, 200, expired) is Ok(Relist))
  assert_true(
    scripted_session(
      200, valid, 200, "{\"type\":\"ERROR\",\"object\":{\"reason\":\"Forbidden\",\"code\":403}}\n",
    )
    is Err(_),
  )
  assert_true(scripted_session(200, valid, 200, "not-json\n") is Err(_))
  assert_true(
    scripted_session(200, valid, 200, "{\"type\":\"ADDED\"") is Err(_),
  )
}

///|
async test "a changed paginated LIST version cannot replace the old cache" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (list, _) = server.accept()
      defer list.close()
      ignore(list.read_request())
      list.send_response(200, "OK")
      list.write(
        "{\"metadata\":{\"resourceVersion\":\"42\",\"continue\":\"next\"},\"items\":[]}",
      )
      list.end_response()
      ignore(list.read_request())
      list.send_response(200, "OK")
      list.write("{\"metadata\":{\"resourceVersion\":\"43\"},\"items\":[]}")
      list.end_response()
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
    )
    let transport = @httptransport.HttpTransport::connect(config)
    defer transport.close()
    let client = @client.DynamicClient::DynamicClient(config)
    let reflector = @reflector.Reflector::Reflector()
    let resource = @resource.GroupVersionResource(
      group="",
      version="v1",
      resource="configmaps",
    )
    assert_true(
      @runtime.sync_once(
        transport,
        client,
        resource,
        Namespace("demo"),
        reflector,
        list_first=true,
      )
      is Err(_),
    )
    assert_eq(reflector.resource_version(), "")
  }
}

///|
async test "continuous runner relists after 410 then tracks the new version" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (list, _) = server.accept()
      defer list.close()
      ignore(list.read_request())
      list.send_response(200, "OK")
      list.write("{\"metadata\":{\"resourceVersion\":\"1\"},\"items\":[]}")
      list.end_response()
      let (first_watch, _) = server.accept()
      ignore(first_watch.read_request())
      first_watch.send_response(410, "Gone")
      first_watch.end_response()
      first_watch.close()
      let second_list = list.read_request()
      assert_true(!second_list.path.contains("watch=1"))
      list.send_response(200, "OK")
      list.write("{\"metadata\":{\"resourceVersion\":\"2\"},\"items\":[]}")
      list.end_response()
      let (second_watch, _) = server.accept()
      defer second_watch.close()
      let request = second_watch.read_request()
      assert_true(request.path.contains("resourceVersion=2"))
      second_watch.send_response(200, "OK")
      second_watch.write(
        "{\"type\":\"BOOKMARK\",\"object\":{\"metadata\":{\"resourceVersion\":\"3\"}}}\n",
      )
      second_watch.end_response()
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
    )
    let transport = @httptransport.HttpTransport::connect(config)
    defer transport.close()
    let client = @client.DynamicClient::DynamicClient(config)
    let reflector = @reflector.Reflector::Reflector()
    let resource = @resource.GroupVersionResource(
      group="",
      version="v1",
      resource="configmaps",
    )
    let task = group.spawn(() => {
      @runtime.run(transport, client, resource, Namespace("demo"), reflector)
    })
    for attempt = 0
        attempt < 100 && reflector.resource_version() != "3"
        attempt = attempt + 1 {
      @async.sleep(10)
    }
    task.cancel()
    assert_eq(reflector.resource_version(), "3")
  }
}
