///|
pub(all) enum EventKind {
  Added
  Modified
  Deleted
  Bookmark
  WatchError
} derive(Debug, Eq)

///|
pub fn EventKind::name(self : EventKind) -> String {
  match self {
    Added => "ADDED"
    Modified => "MODIFIED"
    Deleted => "DELETED"
    Bookmark => "BOOKMARK"
    WatchError => "ERROR"
  }
}

///|
pub struct WatchEvent {
  event_kind : EventKind
  object_value : Json
  version : String
}

///|
pub fn WatchEvent::kind(self : WatchEvent) -> EventKind {
  self.event_kind
}

///|
pub fn WatchEvent::object_json(self : WatchEvent) -> Json {
  self.object_value
}

///|
pub fn WatchEvent::resource_version(self : WatchEvent) -> String {
  self.version
}

///|
fn json_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn event_kind(name : String) -> Result[EventKind, String] {
  match name {
    "ADDED" => Ok(Added)
    "MODIFIED" => Ok(Modified)
    "DELETED" => Ok(Deleted)
    "BOOKMARK" => Ok(Bookmark)
    "ERROR" => Ok(WatchError)
    other => Err("Unsupported watch event type: \{other}")
  }
}

///|
fn object_version(object_value : Json) -> String {
  guard object_value is Object(fields) else { return "" }
  guard fields.get("metadata") is Some(Object(metadata)) else { return "" }
  json_string(metadata, "resourceVersion").unwrap_or("")
}

///|
fn decode_line(line : String) -> Result[WatchEvent, String] {
  let parsed = @json.parse(line) catch {
    _ => return Err("Invalid watch event JSON")
  }
  guard parsed is Object(fields) else {
    return Err("Watch event must be a JSON object")
  }
  guard json_string(fields, "type") is Some(type_name) else {
    return Err("Missing watch event type")
  }
  guard fields.get("object") is Some(object_value) else {
    return Err("Missing watch event object")
  }
  let kind = match event_kind(type_name) {
    Ok(kind) => kind
    Err(message) => return Err(message)
  }
  Ok({ event_kind: kind, object_value, version: object_version(object_value) })
}

///|
/// Incrementally decodes the newline-delimited JSON stream returned by the
/// Kubernetes watch API.
pub struct Decoder {
  mut buffer : String
}

///|
pub fn Decoder::Decoder() -> Decoder {
  { buffer: "" }
}

///|
/// Feed the next arbitrary transport chunk. Only complete lines are decoded;
/// the unfinished tail is retained for the next call.
pub fn Decoder::push(
  self : Decoder,
  chunk : String,
) -> Result[Array[WatchEvent], String] {
  self.buffer = "\{self.buffer}\{chunk}"
  let lines = self.buffer
    .split("\n")
    .map(fn(view) { view.to_owned() })
    .to_array()
  self.buffer = lines.pop().unwrap_or("")
  let events : Array[WatchEvent] = []
  for line in lines {
    if !line.is_empty() {
      match decode_line(line) {
        Ok(event) => events.push(event)
        Err(message) => return Err(message)
      }
    }
  }
  Ok(events)
}
