///|
pub(all) enum Method {
  Get
  Post
  Put
  Patch
  Delete
} derive(Debug, Eq)

///|
pub fn Method::http_name(self : Method) -> String {
  match self {
    Get => "GET"
    Post => "POST"
    Put => "PUT"
    Patch => "PATCH"
    Delete => "DELETE"
  }
}

///|
pub struct Request {
  verb : Method
  path : String
  headers : Map[String, String]
  body : String?
}

///|
pub fn Request::Request(
  verb : Method,
  path : String,
  body? : String,
) -> Request {
  { verb, path, headers: {}, body, }
}

///|
pub fn Request::with_header(
  self : Request,
  name : String,
  value : String,
) -> Request {
  self.headers[name.to_lower()] = value
  self
}

///|
pub fn Request::verb(self : Request) -> Method {
  self.verb
}

///|
pub fn Request::path(self : Request) -> String {
  self.path
}

///|
pub fn Request::header(self : Request, name : String) -> String? {
  self.headers.get(name.to_lower())
}

///|
/// Iterate over normalized request headers without exposing the mutable map.
pub fn Request::headers(self : Request) -> Iter[(String, String)] {
  self.headers.iter()
}

///|
pub fn Request::body(self : Request) -> String? {
  self.body
}

///|
pub struct Response {
  status : Int
  body : String
}

///|
pub fn Response::Response(status~ : Int, body~ : String) -> Response {
  { status, body, }
}

///|
pub fn Response::status(self : Response) -> Int {
  self.status
}

///|
pub fn Response::body(self : Response) -> String {
  self.body
}

///|
pub fn Response::is_success(self : Response) -> Bool {
  self.status >= 200 && self.status < 300
}
