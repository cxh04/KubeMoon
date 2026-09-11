///|
/// Failures detected before a request is written to the network connection.
pub(all) suberror HttpTransportError {
  RequestOriginMismatch(expected~ : String, actual~ : String)
} derive(Debug, Eq)

///|
/// A native HTTP connection bound to one Kubernetes API server.
///
/// Calls to `send` are serialized by the caller. Connection pooling and
/// concurrent request multiplexing are deliberately outside this first
/// executor batch.
pub struct HttpTransport {
  server : String
  client : @http.Client
}

///|
fn trust_root(ca_file : String?) -> @tls.TrustedRoot {
  match ca_file {
    Some(path) => CustomPemFile(path)
    None => SystemRoot
  }
}

///|
fn http_method(request_method : @transport.Method) -> @http.RequestMethod {
  match request_method {
    Get => Get
    Post => Post
    Put => Put
    Patch => Patch
    Delete => Delete
  }
}

///|
fn request_target(
  server : String,
  absolute_url : String,
) -> String raise HttpTransportError {
  guard absolute_url.strip_prefix(server) is Some(suffix) else {
    raise RequestOriginMismatch(expected=server, actual=absolute_url)
  }
  if suffix.is_empty() {
    "/"
  } else if suffix.has_prefix("/") {
    suffix.to_owned()
  } else {
    raise RequestOriginMismatch(expected=server, actual=absolute_url)
  }
}

///|
fn request_headers(request : @transport.Request) -> @http.Headers {
  let headers : @http.Headers = Map([])
  for header in request.headers() {
    let (name, value) = header
    headers[CaseInsensitiveString(name)] = value
  }
  headers
}

///|
/// Connect to the API server and select either system roots or the explicit
/// PEM CA file carried by `ClientConfig`.
pub async fn HttpTransport::connect(
  config : @config.ClientConfig,
) -> HttpTransport {
  let client = @http.Client(config.server(), trust=trust_root(config.ca_file()))
  { server: config.server(), client, }
}

///|
/// Close the reusable HTTP connection. Calling this more than once is safe.
pub fn HttpTransport::close(self : HttpTransport) -> Unit {
  self.client.close()
}

///|
/// Execute one buffered request and read its complete response body.
///
/// The request must target the API server used by `connect`; this prevents an
/// authenticated Kubernetes request from being accidentally replayed against
/// another origin.
pub async fn HttpTransport::send(
  self : HttpTransport,
  request : @transport.Request,
) -> @transport.Response {
  let target = request_target(self.server, request.path())
  self.client.request(
    http_method(request.verb()),
    target,
    extra_headers=request_headers(request),
  )
  match request.body() {
    Some(body) => self.client.write(body)
    None => ()
  }
  let response = self.client.end_request()
  let body = self.client.read_all().text()
  Response(status=response.code, body~)
}
