///|
test "decode an event split across arbitrary chunks" {
  let decoder = @watch.Decoder::Decoder()
  let first = decoder.push(
    "{\"type\":\"ADDED\",\"object\":{\"metadata\":{\"name\":\"settings\",",
  )
  inspect(first.unwrap().length(), content="0")
  let second = decoder.push("\"resourceVersion\":\"12\"}}}\n").unwrap()
  inspect(second.length(), content="1")
  inspect(second[0].kind().name(), content="ADDED")
  inspect(second[0].resource_version(), content="12")
}

///|
test "decode multiple events and preserve the unfinished tail" {
  let decoder = @watch.Decoder::Decoder()
  let events = decoder
    .push(
      "{\"type\":\"MODIFIED\",\"object\":{\"metadata\":{\"resourceVersion\":\"13\"}}}\n{\"type\":\"DELETED\",\"object\":{\"metadata\":{\"resourceVersion\":\"14\"}}}\n{\"type\":",
    )
    .unwrap()
  inspect(events.length(), content="2")
  inspect(events[0].kind().name(), content="MODIFIED")
  inspect(events[1].kind().name(), content="DELETED")
  let bookmark = decoder
    .push(
      "\"BOOKMARK\",\"object\":{\"metadata\":{\"resourceVersion\":\"15\"}}}\n",
    )
    .unwrap()
  inspect(bookmark.length(), content="1")
  inspect(bookmark[0].kind().name(), content="BOOKMARK")
  inspect(bookmark[0].resource_version(), content="15")
}

///|
test "report invalid JSON and unsupported event types" {
  let malformed = @watch.Decoder::Decoder().push("not-json\n")
  match malformed {
    Err(message) => inspect(message, content="Invalid watch event JSON")
    Ok(_) => fail("invalid JSON must be rejected")
  }
  let unsupported = @watch.Decoder::Decoder().push(
    "{\"type\":\"MYSTERY\",\"object\":{}}\n",
  )
  match unsupported {
    Err(message) =>
      inspect(message, content="Unsupported watch event type: MYSTERY")
    Ok(_) => fail("unknown watch types must be rejected")
  }
}
