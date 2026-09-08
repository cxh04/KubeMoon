///|
pub(all) enum Action {
  Continue
  Relist
} derive(Debug, Eq)

///|
pub fn Action::name(self : Action) -> String {
  match self {
    Continue => "CONTINUE"
    Relist => "RELIST"
  }
}

///|
/// Pure LIST/WATCH state machine. Network code supplies snapshots and decoded
/// events; the reflector owns cache replacement, progress, and queueing.
pub struct Reflector {
  store : @store.Store
  queue : @queue.WorkQueue
  mut version : String
}

///|
pub fn Reflector::Reflector() -> Reflector {
  {
    store: Store(),
    queue: WorkQueue(base_delay_ms=100, max_delay_ms=30000),
    version: "",
  }
}

///|
pub fn Reflector::replace(
  self : Reflector,
  snapshot : Array[@object.DynamicObject],
  resource_version : String,
) -> Unit {
  for key in self.store.replace(snapshot) {
    self.queue.add(key)
  }
  self.version = resource_version
}

///|
fn status_expired(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  let by_reason = match fields.get("reason") {
    Some(String("Expired")) => true
    _ => false
  }
  let by_code = match fields.get("code") {
    Some(Number(code, repr=_)) => code == 410.0
    _ => false
  }
  by_reason || by_code
}

///|
pub fn Reflector::apply(
  self : Reflector,
  event : @watch.WatchEvent,
) -> Result[Action, String] {
  let version = event.resource_version()
  if !version.is_empty() {
    self.version = version
  }
  match event.kind() {
    Bookmark => Ok(Continue)
    WatchError =>
      if status_expired(event.object_json()) {
        Ok(Relist)
      } else {
        Err("Kubernetes watch returned an error event")
      }
    Added | Modified =>
      match @object.DynamicObject::try_from_json(event.object_json()) {
        Ok(object) => {
          if self.store.upsert(object) {
            self.queue.add(object.identity())
          }
          Ok(Continue)
        }
        Err(message) => Err(message)
      }
    Deleted =>
      match @object.DynamicObject::try_from_json(event.object_json()) {
        Ok(object) => {
          let key = object.identity()
          if self.store.delete(key) {
            self.queue.add(key)
          }
          Ok(Continue)
        }
        Err(message) => Err(message)
      }
  }
}

///|
pub fn Reflector::resource_version(self : Reflector) -> String {
  self.version
}

///|
pub fn Reflector::queue_length(self : Reflector) -> Int {
  self.queue.length()
}

///|
pub fn Reflector::next_key(self : Reflector) -> String? {
  self.queue.next()
}

///|
pub fn Reflector::done(self : Reflector, key : String) -> Unit {
  self.queue.done(key)
}

///|
pub fn Reflector::retry(self : Reflector, key : String) -> Int {
  self.queue.fail(key)
}

///|
pub fn Reflector::advance(self : Reflector, elapsed_ms : Int) -> Unit {
  self.queue.advance(elapsed_ms)
}
