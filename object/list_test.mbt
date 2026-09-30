///|
test "decode list snapshot keeps items and collection resource version" {
  let body =
    #|{"metadata":{"resourceVersion":"42"},"items":[{"metadata":{"name":"a","namespace":"demo","resourceVersion":"40"}},{"metadata":{"name":"b","namespace":"demo","resourceVersion":"41"}}]}
  let snapshot = @object.decode_list_snapshot(body).unwrap()
  assert_eq(snapshot.resource_version(), "42")
  assert_eq(snapshot.items().length(), 2)
  assert_eq(snapshot.items()[0].identity(), "demo/a")
  assert_eq(snapshot.items()[1].identity(), "demo/b")
}

///|
test "decode list snapshot rejects incomplete collection metadata" {
  assert_true(
    @object.decode_list_snapshot("{\"metadata\":{},\"items\":[]}") is Err(_),
  )
  assert_true(
    @object.decode_list_snapshot("{\"metadata\":{\"resourceVersion\":\"1\"}}")
    is Err(_),
  )
}

///|
test "decode list snapshot rejects invalid item with its index" {
  let result = @object.decode_list_snapshot(
    "{\"metadata\":{\"resourceVersion\":\"1\"},\"items\":[{\"metadata\":{\"name\":\"ok\"}},{}]}",
  )
  guard result is Err(message) else { fail("expected invalid item") }
  assert_true(message.contains("items[1]"))
}
