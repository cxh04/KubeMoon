///|
/// FIFO transport double for deterministic client and reflector tests.
pub struct ScriptedTransport {
  responses : Array[@transport.Response]
  requests : Array[@transport.Request]
  mut cursor : Int
}

///|
pub fn ScriptedTransport::ScriptedTransport(
  responses : Array[@transport.Response],
) -> ScriptedTransport {
  { responses, requests: [], cursor: 0 }
}

///|
pub fn ScriptedTransport::send(
  self : ScriptedTransport,
  request : @transport.Request,
) -> Result[@transport.Response, String] {
  self.requests.push(request)
  if self.cursor >= self.responses.length() {
    return Err("Fake transport script exhausted")
  }
  let response = self.responses[self.cursor]
  self.cursor = self.cursor + 1
  Ok(response)
}

///|
pub fn ScriptedTransport::request_count(self : ScriptedTransport) -> Int {
  self.requests.length()
}

///|
pub fn ScriptedTransport::request_at(
  self : ScriptedTransport,
  index : Int,
) -> @transport.Request? {
  if index < 0 || index >= self.requests.length() {
    None
  } else {
    Some(self.requests[index])
  }
}
