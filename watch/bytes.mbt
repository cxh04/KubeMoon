///|
/// Frames watch events by newline before decoding UTF-8. A network read may
/// split a multibyte character, so decoding each read independently is unsafe.
pub struct ByteDecoder {
  mut pending : Array[Byte]
  lines : Decoder
}

///|
pub fn ByteDecoder::ByteDecoder() -> ByteDecoder {
  { pending: [], lines: Decoder(), }
}

///|
/// Feed arbitrary network bytes and return all complete watch events.
pub fn ByteDecoder::push(
  self : ByteDecoder,
  chunk : Bytes,
) -> Result[Array[WatchEvent], String] {
  let events : Array[WatchEvent] = []
  for byte in chunk {
    if byte == b'\n' {
      let line = @utf8.decode(Bytes::from_array(self.pending)) catch {
        _ => return Err("Invalid UTF-8 in watch event")
      }
      self.pending = []
      match self.lines.push("\{line}\n") {
        Ok(complete) =>
          for event in complete {
            events.push(event)
          }
        Err(message) => return Err(message)
      }
    } else {
      self.pending.push(byte)
    }
  }
  Ok(events)
}

///|
/// Complete a stream only if no unterminated event remains.
pub fn ByteDecoder::finish(self : ByteDecoder) -> Result[Unit, String] {
  if self.pending.is_empty() {
    Ok(())
  } else {
    Err("Truncated watch event at EOF")
  }
}
