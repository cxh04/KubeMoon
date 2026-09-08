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
