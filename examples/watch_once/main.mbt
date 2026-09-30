///|
/// A real local HTTP stream, without requiring a Kubernetes cluster.
async fn main {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg() <| () => {
      // HttpTransport keeps its buffered connection; WATCH uses another one.
      let (idle, _) = server.accept()
      defer idle.close()
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      if !request.path.contains("watch=1") {
        fail("expected a watch request")
      }
      connection.send_response(200, "OK")
      connection..write("{\"type\":\"BOOK").flush()
      @async.sleep(10)
      connection.write(
        "MARK\",\"object\":{\"metadata\":{\"resourceVersion\":\"12\"}}}\n",
      )
      connection.write(
        "{\"type\":\"ADDED\",\"object\":{\"metadata\":{\"name\":\"中文\",\"resourceVersion\":\"13\"}}}\n",
      )
      connection.end_response()
    }

    let config = @config.ClientConfig(
      server="http://127.0.0.1:\{server.addr.port()}",
      bearer_token="demo-token",
    )
    let client = @client.DynamicClient::DynamicClient(config)
    let transport = @httptransport.HttpTransport::connect(config)
    defer transport.close()
    let configmaps = @resource.GroupVersionResource(
      group="",
      version="v1",
      resource="configmaps",
    )
    let stream = transport.open_stream(
      client.watch_request(configmaps, Namespace("demo"), resource_version="12"),
    )
    defer stream.close()
    if stream.status() != 200 {
      fail("watch HTTP status: \{stream.status()}")
    }
    let decoder = @watch.ByteDecoder::ByteDecoder()
    while stream.read_some(7) is Some(chunk) {
      for event in decoder.push(chunk).unwrap() {
        println("\{event.kind().name()} \{event.resource_version()}")
      }
    }
    decoder.finish().unwrap()
  }
}
