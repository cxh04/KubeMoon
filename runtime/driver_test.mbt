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
