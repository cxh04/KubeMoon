///|
pub(all) enum WatchOutcome {
  Resume
  Relist
  Retry
} derive(Debug, Eq)

///|
pub extend WatchOutcome with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WatchOutcome with Eq::{not_equal, equal}

///|
pub suberror RuntimeError {
  Failed(String)
}

///|
/// One LIST/WATCH session. A fresh session takes its WATCH version from the
/// collection metadata, never from an individual item. The caller owns the
/// reflector and can inspect its queue after this function returns.
pub async fn sync_once(
  transport : @httptransport.HttpTransport,
  client : @client.DynamicClient,
  resource : @resource.GroupVersionResource,
  scope : @resource.Scope,
  reflector : @reflector.Reflector,
  list_first~ : Bool,
) -> Result[WatchOutcome, String] {
  if list_first {
    let objects : Array[@object.DynamicObject] = []
    let mut continuation : String? = None
    let mut version = ""
    for ;; {
      let request = match continuation {
        Some(token) => client.list_page_request(resource, scope, token)
        None => client.list_request(resource, scope)
      }
      let response = transport.send(request)
      if !response.is_success() {
        let status = response.status()
        if status == 410 || status == 429 || status >= 500 {
          return Ok(Retry)
        }
        return Err(
          "Kubernetes LIST failed with HTTP \{status}: \{response.body()}",
        )
      }
      let snapshot = match @object.decode_list_snapshot(response.body()) {
        Ok(snapshot) => snapshot
        Err(message) => return Err(message)
      }
      if version.is_empty() {
        version = snapshot.resource_version()
      } else if version != snapshot.resource_version() {
        return Err("Paginated LIST resourceVersion changed between pages")
      }
      for object in snapshot.items() {
        objects.push(object)
      }
      match snapshot.continue_token() {
        Some(token) => continuation = Some(token)
        None => break
      }
    }
    reflector.replace(objects, version)
  }
  let stream = transport.open_stream(
    client.watch_request(
      resource,
      scope,
      resource_version=reflector.resource_version(),
    ),
  )
  defer stream.close()
  let status = stream.status()
  if status == 410 {
    return Ok(Relist)
  }
  if status == 429 || status >= 500 {
    return Ok(Retry)
  }
  if status < 200 || status >= 300 {
    return Err("Kubernetes WATCH failed with HTTP \{status}")
  }
  let decoder = @watch.ByteDecoder::ByteDecoder()
  while stream.read_some(4096) is Some(chunk) {
    let events = match decoder.push(chunk) {
      Ok(events) => events
      Err(message) => return Err(message)
    }
    for event in events {
      match reflector.apply(event) {
        Ok(Relist) => return Ok(Relist)
        Ok(Continue) => ()
        Err(message) => return Err(message)
      }
    }
  }
  match decoder.finish() {
    Ok(_) => Ok(Resume)
    Err(message) => Err(message)
  }
}

///|
/// Keep the reflector current until its containing async task is cancelled.
/// Recoverable I/O errors retry from the last version; an expired version
/// forces a new LIST. Malformed data and authorization failures stop visibly.
pub async fn run(
  transport : @httptransport.HttpTransport,
  client : @client.DynamicClient,
  resource : @resource.GroupVersionResource,
  scope : @resource.Scope,
  reflector : @reflector.Reflector,
) -> Unit {
  let mut list_first = true
  let mut delay_ms = 100
  for ;; {
    let result = sync_once(
      transport,
      client,
      resource,
      scope,
      reflector,
      list_first~,
    ) catch {
      error => {
        if @async.is_cancellation_error(error) {
          raise error
        }
        Ok(Retry)
      }
    }
    match result {
      Err(message) => raise RuntimeError::Failed(message)
      Ok(Relist) => {
        list_first = true
        delay_ms = 100
        @async.sleep(100)
      }
      Ok(Resume) => {
        list_first = false
        delay_ms = 100
        @async.sleep(100)
      }
      Ok(Retry) => {
        @async.sleep(delay_ms)
        delay_ms = (delay_ms * 2).min(30000)
      }
    }
  }
}
