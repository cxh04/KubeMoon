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

///|
test "byte decoder keeps UTF-8 characters across network chunks" {
  let decoder = @watch.ByteDecoder::ByteDecoder()
  let first = @utf8.encode(
      "{\"type\":\"ADDED\",\"object\":{\"metadata\":{\"name\":\"",
    ) +
    b"\xE4"
  inspect(decoder.push(first).unwrap().length(), content="0")
  let second = b"\xB8\xAD" +
    @utf8.encode("文\",\"resourceVersion\":\"9\"}}}\n")
  let events = decoder.push(second).unwrap()
  inspect(events.length(), content="1")
  inspect(events[0].kind().name(), content="ADDED")
  inspect(events[0].resource_version(), content="9")
  inspect(decoder.finish() is Ok(_), content="true")
}

///|
test "byte decoder reads multiple events and ignores empty lines" {
  let decoder = @watch.ByteDecoder::ByteDecoder()
  let events = decoder
    .push(
      @utf8.encode(
        "\n{\"type\":\"BOOKMARK\",\"object\":{}}\n{\"type\":\"DELETED\",\"object\":{}}\n",
      ),
    )
    .unwrap()
  inspect(events.length(), content="2")
  inspect(events[0].kind().name(), content="BOOKMARK")
  inspect(events[1].kind().name(), content="DELETED")
}

///|
test "byte decoder rejects malformed UTF-8 and incomplete EOF" {
  let invalid = @watch.ByteDecoder::ByteDecoder().push(b"\xFF\n")
  match invalid {
    Err(message) => inspect(message, content="Invalid UTF-8 in watch event")
    Ok(_) => fail("invalid UTF-8 must be rejected")
  }
  let decoder = @watch.ByteDecoder::ByteDecoder()
  inspect(decoder.push(b"{\"type\":").unwrap().length(), content="0")
  match decoder.finish() {
    Err(message) => inspect(message, content="Truncated watch event at EOF")
    Ok(_) => fail("incomplete event must be rejected")
  }
}
