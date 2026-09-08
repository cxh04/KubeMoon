///|
/// In-memory cache populated by LIST snapshots and WATCH events.
pub struct Store {
  objects : Map[String, @object.DynamicObject]
}

///|
pub fn Store::Store() -> Store {
  { objects: Map([]), }
}

///|
pub fn Store::length(self : Store) -> Int {
  self.objects.length()
}

///|
pub fn Store::get(self : Store, key : String) -> @object.DynamicObject? {
  self.objects.get(key)
}

///|
/// Add or replace an object. Returns true only when a new identity or resource
/// version was observed, which prevents duplicate reconcile work after a
/// watch reconnect.
pub fn Store::upsert(self : Store, object : @object.DynamicObject) -> Bool {
  let key = object.identity()
  match self.objects.get(key) {
    Some(current) if current.resource_version() == object.resource_version() =>
      false
    _ => {
      self.objects[key] = object
      true
    }
  }
}

///|
/// Delete by stable identity. Repeated deletes are harmless.
pub fn Store::delete(self : Store, key : String) -> Bool {
  if self.objects.contains(key) {
    self.objects.remove(key)
    true
  } else {
    false
  }
}

///|
/// Atomically replace the cache with a LIST result and return every identity
/// whose existence or resource version changed.
pub fn Store::replace(
  self : Store,
  snapshot : Array[@object.DynamicObject],
) -> Array[String] {
  let replacement : Map[String, @object.DynamicObject] = Map([])
  let changed : Array[String] = []
  for object in snapshot {
    let key = object.identity()
    match self.objects.get(key) {
      Some(current) if current.resource_version() == object.resource_version() =>
        ()
      _ => changed.push(key)
    }
    replacement[key] = object
  }
  for key in self.objects.keys() {
    if !replacement.contains(key) {
      changed.push(key)
    }
  }
  self.objects.clear()
  for key_object in replacement.iter() {
    let (key, object) = key_object
    self.objects[key] = object
  }
  changed
}
