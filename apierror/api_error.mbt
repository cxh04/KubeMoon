///|
/// A non-success response from the Kubernetes API.
pub struct ApiError {
  status : Int
  reason_value : String
  message_value : String
}

///|
fn status_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn decode_status(body : String) -> (String?, String?) {
  let parsed = @json.parse(body) catch { _ => return (None, None) }
  match parsed {
    Object(fields) =>
      (status_string(fields, "reason"), status_string(fields, "message"))
    _ => (None, None)
  }
}

///|
/// Build a structured error from a response. Kubernetes `Status` documents are
/// decoded when possible; proxies and load balancers may still return plain
/// text, so the response body remains a useful fallback message.
pub fn ApiError::from_response(status : Int, body : String) -> ApiError {
  let (reason, message) = decode_status(body)
  {
    status,
    reason_value: reason.unwrap_or("HTTP \{status}"),
    message_value: message.unwrap_or(body),
  }
}

///|
pub fn ApiError::status_code(self : ApiError) -> Int {
  self.status
}

///|
pub fn ApiError::reason(self : ApiError) -> String {
  self.reason_value
}

///|
pub fn ApiError::message(self : ApiError) -> String {
  self.message_value
}

///|
pub fn ApiError::is_not_found(self : ApiError) -> Bool {
  self.status == 404 || self.reason_value == "NotFound"
}

///|
pub fn ApiError::is_conflict(self : ApiError) -> Bool {
  self.status == 409 || self.reason_value == "Conflict"
}

///|
/// `410 Gone` is handled by the reflector as a relist signal, not as an
/// ordinary transport retry.
pub fn ApiError::is_expired(self : ApiError) -> Bool {
  self.status == 410 || self.reason_value == "Expired"
}

///|
pub fn ApiError::is_retryable(self : ApiError) -> Bool {
  self.status == 429 || self.status >= 500
}
