///|
fn mirror_without_finalizer() -> @object.DynamicObject raise {
  @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"mirror\",\"namespace\":\"ops\",\"uid\":\"uid-1\",\"resourceVersion\":\"5\"},\"spec\":{\"source\":{\"namespace\":\"source\",\"name\":\"settings\"},\"targets\":[\"west\"]}}",
    ),
  )
}

///|
fn mirror_with_finalizer() -> @object.DynamicObject raise {
  @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"mirror\",\"namespace\":\"ops\",\"uid\":\"uid-1\",\"resourceVersion\":\"6\",\"generation\":1,\"finalizers\":[\"cxh04.github.io/kubemoon-cleanup\"]},\"spec\":{\"source\":{\"namespace\":\"source\",\"name\":\"settings\"},\"targets\":[\"west\"]}}",
    ),
  )
}

///|
async test "first reconcile adds a finalizer before touching targets" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      assert_true(request.path.contains("/configmirrors/mirror"))
      assert_true(!request.path.contains("/status"))
      connection.send_response(200, "OK")
      connection.write("{}")
      connection.end_response()
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
    )
    let transport = @httptransport.HttpTransport::connect(config)
    defer transport.close()
    let client = @client.DynamicClient::DynamicClient(config)
    let reconciler = @operator.ConfigMirrorReconciler::ConfigMirrorReconciler(
      transport, client,
    )
    assert_true(
      reconciler.reconcile("ops/mirror", Some(mirror_without_finalizer()))
      is Ok(_),
    )
  }
}

///|
async test "active reconcile fetches source creates target and writes status" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (connection, _) = server.accept()
      defer connection.close()
      let source = connection.read_request()
      assert_true(
        source.path.contains("/namespaces/source/configmaps/settings"),
      )
      connection.send_response(200, "OK")
      connection.write(
        "{\"metadata\":{\"name\":\"settings\",\"namespace\":\"source\",\"resourceVersion\":\"9\"},\"data\":{\"key\":\"value\"}}",
      )
      connection.end_response()
      let target = connection.read_request()
      assert_true(target.path.contains("/namespaces/west/configmaps/settings"))
      connection.send_response(404, "Not Found")
      connection.write("{}")
      connection.end_response()
      let create = connection.read_request()
      assert_true(create.path.contains("/namespaces/west/configmaps"))
      connection.send_response(201, "Created")
      connection.write("{}")
      connection.end_response()
      let status = connection.read_request()
      assert_true(status.path.contains("/configmirrors/mirror/status"))
      connection.send_response(200, "OK")
      connection.write("{}")
      connection.end_response()
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
    )
    let transport = @httptransport.HttpTransport::connect(config)
    defer transport.close()
    let client = @client.DynamicClient::DynamicClient(config)
    let reconciler = @operator.ConfigMirrorReconciler::ConfigMirrorReconciler(
      transport, client,
    )
    assert_true(
      reconciler.reconcile("ops/mirror", Some(mirror_with_finalizer())) is Ok(_),
    )
  }
}

///|
test "ConfigMap events schedule only related mirrors" {
  let mirrors = @reflector.Reflector::Reflector()
  mirrors.replace([mirror_with_finalizer()], "1")
  assert_eq(mirrors.next_key(), Some("ops/mirror"))
  mirrors.done("ops/mirror")
  assert_eq(@operator.enqueue_affected(mirrors, "unrelated/settings"), 0)
  assert_eq(mirrors.queue_length(), 0)
  assert_eq(@operator.enqueue_affected(mirrors, "source/settings"), 1)
  assert_eq(mirrors.next_key(), Some("ops/mirror"))
  mirrors.done("ops/mirror")
  assert_eq(@operator.enqueue_affected(mirrors, "west/settings"), 1)
}

///|
async test "deletion waits for managed target to vanish before removing finalizer" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      let (connection, _) = server.accept()
      defer connection.close()
      let first = connection.read_request()
      assert_true(first.path.contains("/namespaces/west/configmaps/settings"))
      connection.send_response(200, "OK")
      connection.write(
        "{\"metadata\":{\"name\":\"settings\",\"namespace\":\"west\",\"resourceVersion\":\"3\",\"annotations\":{\"cxh04.github.io/kubemoon-owner-uid\":\"uid-1\"}}}",
      )
      connection.end_response()
      let delete = connection.read_request()
      assert_true(delete.path.contains("/namespaces/west/configmaps/settings"))
      connection.send_response(200, "OK")
      connection.write("{}")
      connection.end_response()
      let second = connection.read_request()
      assert_true(second.path.contains("/namespaces/west/configmaps/settings"))
      connection.send_response(404, "Not Found")
      connection.write("{}")
      connection.end_response()
      let patch = connection.read_request()
      assert_true(patch.path.contains("/configmirrors/mirror"))
      connection.send_response(200, "OK")
      connection.write("{}")
      connection.end_response()
    }
    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
    )
    let transport = @httptransport.HttpTransport::connect(config)
    defer transport.close()
    let client = @client.DynamicClient::DynamicClient(config)
    let reconciler = @operator.ConfigMirrorReconciler::ConfigMirrorReconciler(
      transport, client,
    )
    let deleting = @object.DynamicObject::from_json(
      @json.parse(
        "{\"metadata\":{\"name\":\"mirror\",\"namespace\":\"ops\",\"uid\":\"uid-1\",\"resourceVersion\":\"7\",\"deletionTimestamp\":\"2026-09-30T00:00:00Z\",\"finalizers\":[\"cxh04.github.io/kubemoon-cleanup\"]},\"spec\":{\"source\":{\"namespace\":\"source\",\"name\":\"settings\"},\"targets\":[\"west\"]}}",
      ),
    )
    assert_true(reconciler.reconcile("ops/mirror", Some(deleting)) is Err(_))
    assert_true(reconciler.reconcile("ops/mirror", Some(deleting)) is Ok(_))
  }
}
