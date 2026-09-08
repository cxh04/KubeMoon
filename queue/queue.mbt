///|
/// Deterministic work queue with Kubernetes-style dirty-key coalescing and
/// exponential retry delays. Time advances explicitly, which keeps controller
/// tests free from sleeps.
pub struct WorkQueue {
  pending : Array[String]
  pending_keys : Map[String, Bool]
  processing : Map[String, Bool]
  dirty : Map[String, Bool]
  failures : Map[String, Int]
  delayed_until : Map[String, Int]
  base_delay_ms : Int
  max_delay_ms : Int
  mut now_ms : Int
}

///|
pub fn WorkQueue::WorkQueue(
  base_delay_ms~ : Int,
  max_delay_ms~ : Int,
) -> WorkQueue {
  {
    pending: [],
    pending_keys: Map([]),
    processing: Map([]),
    dirty: Map([]),
    failures: Map([]),
    delayed_until: Map([]),
    base_delay_ms,
    max_delay_ms,
    now_ms: 0,
  }
}

///|
fn WorkQueue::enqueue(self : WorkQueue, key : String) -> Unit {
  if !self.pending_keys.contains(key) {
    self.pending.push(key)
    self.pending_keys[key] = true
  }
}

///|
pub fn WorkQueue::length(self : WorkQueue) -> Int {
  self.pending.length()
}

///|
/// Add a reconcile key. Duplicate pending keys collapse; an event observed
/// while the key is processing marks it dirty for exactly one later pass.
pub fn WorkQueue::add(self : WorkQueue, key : String) -> Unit {
  if self.processing.contains(key) {
    self.dirty[key] = true
  } else if !self.delayed_until.contains(key) {
    self.enqueue(key)
  }
}

///|
pub fn WorkQueue::next(self : WorkQueue) -> String? {
  if self.pending.is_empty() {
    return None
  }
  let key = self.pending.remove(0)
  self.pending_keys.remove(key)
  self.processing[key] = true
  Some(key)
}

///|
/// Complete a successful reconciliation and reset its retry history.
pub fn WorkQueue::done(self : WorkQueue, key : String) -> Unit {
  self.processing.remove(key)
  self.failures.remove(key)
  if self.dirty.contains(key) {
    self.dirty.remove(key)
    self.enqueue(key)
  }
}

///|
fn retry_delay(base : Int, maximum : Int, failures : Int) -> Int {
  let mut delay = base
  for step = 1; step < failures; step = step + 1 {
    delay = (delay * 2).min(maximum)
  }
  delay.min(maximum)
}

///|
/// Complete a failed reconciliation and schedule its next attempt. Returns the
/// selected delay so callers can surface it in traces and metrics.
pub fn WorkQueue::fail(self : WorkQueue, key : String) -> Int {
  self.processing.remove(key)
  self.dirty.remove(key)
  let failures = self.failures.get(key).unwrap_or(0) + 1
  self.failures[key] = failures
  let delay = retry_delay(self.base_delay_ms, self.max_delay_ms, failures)
  self.delayed_until[key] = self.now_ms + delay
  delay
}

///|
/// Advance the virtual clock and make every due retry available.
pub fn WorkQueue::advance(self : WorkQueue, elapsed_ms : Int) -> Unit {
  self.now_ms = self.now_ms + elapsed_ms
  let ready : Array[String] = []
  for entry in self.delayed_until.iter() {
    let (key, deadline) = entry
    if deadline <= self.now_ms {
      ready.push(key)
    }
  }
  for key in ready {
    self.delayed_until.remove(key)
    self.enqueue(key)
  }
}
