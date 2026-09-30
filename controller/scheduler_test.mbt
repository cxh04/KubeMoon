///|
async test "controller receives latest cached object and completes key" {
  let reflector = @reflector.Reflector::Reflector()
  let object = @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"demo\",\"namespace\":\"ns\",\"resourceVersion\":\"1\"}}",
    ),
  )
  reflector.replace([object], "1")
  let calls : Array[String] = []
  assert_true(
    @controller.process_next(reflector, (key, current) => {
      calls.push(key)
      assert_true(current is Some(_))
      Ok(())
    }),
  )
  assert_eq(calls, ["ns/demo"])
  assert_eq(reflector.queue_length(), 0)
}

///|
async test "controller retries a failed key after virtual time advances" {
  let reflector = @reflector.Reflector::Reflector()
  let object = @object.DynamicObject::from_json(
    @json.parse("{\"metadata\":{\"name\":\"demo\",\"resourceVersion\":\"1\"}}"),
  )
  reflector.replace([object], "1")
  let attempts : Array[Int] = []
  let reconcile : async (String, @object.DynamicObject?) -> Result[Unit, String] = (
    key,
    _,
  ) => {
    assert_eq(key, "demo")
    attempts.push(1)
    if attempts.length() == 1 {
      Err("temporary failure")
    } else {
      Ok(())
    }
  }
  assert_true(@controller.process_next(reflector, reconcile))
  assert_true(!@controller.process_next(reflector, reconcile))
  reflector.advance(99)
  assert_true(!@controller.process_next(reflector, reconcile))
  reflector.advance(1)
  assert_true(@controller.process_next(reflector, reconcile))
  assert_eq(attempts.length(), 2)
}
