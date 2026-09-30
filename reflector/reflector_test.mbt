///|
fn event(line : String) -> @watch.WatchEvent {
  let decoder = @watch.Decoder::Decoder()
  decoder.push("\{line}\n").unwrap()[0]
}

///|
fn listed(name : String, version : String) -> @object.DynamicObject {
  @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"\{name}\",\"namespace\":\"team-a\",\"resourceVersion\":\"\{version}\"}}",
    ) catch {
      _ => abort("test fixture must be valid JSON")
    },
  )
}

///|
test "replace a snapshot then coalesce repeated watch versions" {
  let reflector = @reflector.Reflector::Reflector()
  reflector.replace([listed("settings", "10")], "10")
  inspect(reflector.next_key().unwrap_or(""), content="team-a/settings")
  reflector.done("team-a/settings")
  let modified = event(
    "{\"type\":\"MODIFIED\",\"object\":{\"metadata\":{\"name\":\"settings\",\"namespace\":\"team-a\",\"resourceVersion\":\"11\"}}}",
  )
  inspect(reflector.apply(modified).unwrap().name(), content="CONTINUE")
  reflector.apply(modified) |> ignore
  inspect(reflector.resource_version(), content="11")
  inspect(reflector.queue_length(), content="1")
}

///|
test "bookmark advances progress without scheduling reconcile" {
  let reflector = @reflector.Reflector::Reflector()
  let bookmark = event(
    "{\"type\":\"BOOKMARK\",\"object\":{\"metadata\":{\"resourceVersion\":\"25\"}}}",
  )
  reflector.apply(bookmark) |> ignore
  inspect(reflector.resource_version(), content="25")
  inspect(reflector.queue_length(), content="0")
}

///|
test "410 watch errors request a fresh LIST" {
  let reflector = @reflector.Reflector::Reflector()
  let expired = event(
    "{\"type\":\"ERROR\",\"object\":{\"kind\":\"Status\",\"reason\":\"Expired\",\"code\":410}}",
  )
  inspect(reflector.apply(expired).unwrap().name(), content="RELIST")
}

///|
test "delete removes cached object and malformed identities fail visibly" {
  let reflector = @reflector.Reflector::Reflector()
  reflector.replace([listed("settings", "10")], "10")
  assert_eq(reflector.next_key(), Some("team-a/settings"))
  reflector.done("team-a/settings")
  let deleted = event(
    "{\"type\":\"DELETED\",\"object\":{\"metadata\":{\"name\":\"settings\",\"namespace\":\"team-a\",\"resourceVersion\":\"11\"}}}",
  )
  assert_true(reflector.apply(deleted) is Ok(_))
  assert_true(reflector.get("team-a/settings") is None)
  assert_eq(reflector.next_key(), Some("team-a/settings"))
  let invalid_added = event("{\"type\":\"ADDED\",\"object\":{}}")
  let invalid_deleted = event("{\"type\":\"DELETED\",\"object\":{}}")
  assert_true(reflector.apply(invalid_added) is Err(_))
  assert_true(reflector.apply(invalid_deleted) is Err(_))
}

///|
test "non-expired watch status remains an error" {
  let reflector = @reflector.Reflector::Reflector()
  let forbidden = event(
    "{\"type\":\"ERROR\",\"object\":{\"reason\":\"Forbidden\",\"code\":403}}",
  )
  assert_true(reflector.apply(forbidden) is Err(_))
}
