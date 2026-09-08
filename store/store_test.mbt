///|
fn dynamic(name : String, version : String) -> @object.DynamicObject {
  @object.DynamicObject::from_json(
    @json.parse(
      "{\"metadata\":{\"name\":\"\{name}\",\"namespace\":\"team-a\",\"resourceVersion\":\"\{version}\"}}",
    ) catch {
      _ => abort("test fixture must be valid JSON")
    },
  )
}

///|
test "replace a LIST snapshot and report changed keys" {
  let store = @store.Store::Store()
  let first = store.replace([dynamic("a", "1"), dynamic("b", "1")])
  first.sort()
  inspect(first.join(", "), content="team-a/a, team-a/b")
  inspect(store.length(), content="2")

  let second = store.replace([dynamic("a", "1")])
  inspect(second.join(", "), content="team-a/b")
  inspect(store.get("team-a/b") is None, content="true")
}

///|
test "ignore an unchanged resource version and retain updates" {
  let store = @store.Store::Store()
  inspect(store.upsert(dynamic("settings", "7")), content="true")
  inspect(store.upsert(dynamic("settings", "7")), content="false")
  inspect(store.upsert(dynamic("settings", "8")), content="true")
  inspect(store.get("team-a/settings").unwrap().resource_version(), content="8")
}

///|
test "delete is idempotent" {
  let store = @store.Store::Store()
  store.upsert(dynamic("settings", "1")) |> ignore
  inspect(store.delete("team-a/settings"), content="true")
  inspect(store.delete("team-a/settings"), content="false")
}
