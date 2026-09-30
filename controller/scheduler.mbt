///|
/// Process at most one dirty key. Reconciliation receives the newest cached
/// object, or `None` when the object was deleted. Failures stay in the queue
/// with exponential delay; a successful retry resets that delay.
pub async fn process_next(
  reflector : @reflector.Reflector,
  reconcile : async (String, @object.DynamicObject?) -> Result[Unit, String],
) -> Bool {
  guard reflector.next_key() is Some(key) else { return false }
  let outcome = reconcile(key, reflector.get(key)) catch {
    error => {
      if @async.is_cancellation_error(error) {
        reflector.retry(key) |> ignore
        raise error
      }
      Err(error.to_string())
    }
  }
  match outcome {
    Ok(_) => reflector.done(key)
    Err(_) => reflector.retry(key) |> ignore
  }
  true
}

///|
/// Drain changes continuously while the corresponding LIST/WATCH task runs.
/// `Reflector` owns the virtual retry clock; wall time is only advanced here.
pub async fn run(
  reflector : @reflector.Reflector,
  reconcile : async (String, @object.DynamicObject?) -> Result[Unit, String],
) -> Unit {
  for ;; {
    if !process_next(reflector, reconcile) {
      @async.sleep(50)
      reflector.advance(50)
    }
  }
}
